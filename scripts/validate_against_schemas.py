#!/usr/bin/env python3
"""Validate the Customer360 request bodies and saved example responses in the Postman
collection against the published XSDs in TransactionTree/transactiontree-schemas.

    python3 scripts/validate_against_schemas.py postman/collection.json <path-to-schemas-repo>

The portal links to those schemas, so the two must agree. Each request whose endpoint has a
published schema is checked:
  - the XmlInput request body                  -> <operation>-request.xsd
  - the request body saved with each example   -> <operation>-request.xsd
    (skipped when the example shows an error code: those requests are often invalid on purpose)
  - every saved example response body          -> <operation>-response*.xsd (any one may match)

Postman variables such as {{today}} are replaced with sample values before validation.
Uses lxml when it is installed, otherwise the `xmllint` command (libxml2-utils). Standard
library only otherwise. Exit status 1 when anything fails to validate.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# endpoint (last URL path segment) -> schema directory under c360/3.0
SCHEMA_DIRS = {
    'findCustomersB': 'Customer/findCustomersB',
    'getPersonCompleteDetailsB': 'Customer/getPersonCompleteDetailsB',
    'updateCustomer': 'Customer/updateCustomerB',
    'updateCustomerB': 'Customer/updateCustomerB',
    'couponAuthentication': 'Coupon/couponAuthentication',
    'couponPost': 'Coupon/couponPost',
    'customerCertificateSearch': 'Coupon/customerCertificateSearch',
    'getOrderHeaderDetailsB': 'Order/getOrderHeaderDetailsB',
    'getOrderDetailsB': 'Order/getOrderDetailsB',
    'getOrderDetailsC': 'Order/getOrderDetailsC',
    'getOrderHeaderDetailsC': 'Order/getOrderHeaderDetailsC',
}

# Postman variables that need a specific sample value to satisfy an enumeration
VARIABLE_SAMPLES = {'REQ_COUPON_TYPE': 'SERIALIZE'}
DEFAULT_SAMPLE = '1'
ERROR_CODE = re.compile(r'<RESPONSE_CODE>\s*E\d')

try:
    from lxml import etree
except ImportError:  # pragma: no cover - CI path
    etree = None


def fill_variables(text):
    return re.sub(r'\{\{\s*([^}\s]+)\s*\}\}', lambda m: VARIABLE_SAMPLES.get(m.group(1), DEFAULT_SAMPLE), text)


def walk(items, path=()):
    for it in items:
        if 'item' in it:
            yield from walk(it['item'], path + (it.get('name', ''),))
        else:
            yield path, it


def request_xml(request):
    body = request.get('body') or {}
    mode = body.get('mode')
    if mode == 'raw':
        return body.get('raw')
    for part in body.get(mode) or []:
        if (part.get('key') or '').lower() == 'xmlinput':
            return part.get('value')
    return None


def validate(xml_text, xsd_paths):
    """Return (ok, message). ok when the document validates against any of the schemas."""
    xml_text = fill_variables(xml_text).strip()
    if etree is not None:
        try:
            doc = etree.fromstring(xml_text.encode('utf-8'))
        except etree.XMLSyntaxError as exc:
            return False, 'not well-formed XML: %s' % exc
        message = 'no schema found'
        for xsd in xsd_paths:
            schema = etree.XMLSchema(etree.parse(xsd))
            if schema.validate(doc):
                return True, ''
            message = str(schema.error_log.last_error.message)
        return False, message
    if not shutil.which('xmllint'):
        sys.exit('validate_against_schemas: install lxml or xmllint (libxml2-utils)')
    with tempfile.NamedTemporaryFile('w', suffix='.xml', delete=False, encoding='utf-8') as handle:
        handle.write(xml_text)
        name = handle.name
    try:
        message = 'no schema found'
        for xsd in xsd_paths:
            run = subprocess.run(['xmllint', '--noout', '--schema', xsd, name], capture_output=True, text=True)
            if run.returncode == 0:
                return True, ''
            message = (run.stderr.strip().splitlines() or ['xmllint failed'])[0].replace(name, 'document')
        return False, message
    finally:
        os.unlink(name)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    collection_path, schemas_root = sys.argv[1], sys.argv[2]
    with open(collection_path, encoding='utf-8') as handle:
        collection = json.load(handle)
    collection = collection.get('collection', collection)
    base = os.path.join(schemas_root, 'c360', '3.0')
    if not os.path.isdir(base):
        sys.exit('validate_against_schemas: %s is not the schemas repository' % schemas_root)

    checked = failed = 0
    for path, item in walk(collection.get('item', [])):
        request = item.get('request') or {}
        url = request.get('url')
        raw_url = url.get('raw') if isinstance(url, dict) else (url or '')
        endpoint = raw_url.split('?')[0].rstrip('/').split('/')[-1]
        if endpoint not in SCHEMA_DIRS:
            continue
        schema_dir = os.path.join(base, *SCHEMA_DIRS[endpoint].split('/'))
        request_xsds = sorted(glob.glob(os.path.join(schema_dir, '*-request*.xsd')))
        response_xsds = sorted(glob.glob(os.path.join(schema_dir, '*-response*.xsd')))
        label = ' / '.join(path + (item.get('name', ''),))

        documents = []
        body = request_xml(request)
        if body and body.strip():
            documents.append(('request body', body, request_xsds))
        for example in item.get('response') or []:
            saved = request_xml(example.get('originalRequest') or {})
            # An error example often exists to show a deliberately bad request (a wrong coupon
            # type, an empty code), so its saved request is only checked for non-error examples.
            if saved and saved.strip() and not ERROR_CODE.search(example.get('body') or ''):
                documents.append(('request saved with example "%s"' % example.get('name'), saved, request_xsds))
            if (example.get('body') or '').strip():
                documents.append(('example "%s"' % example.get('name'), example['body'], response_xsds))

        for what, xml_text, xsds in documents:
            checked += 1
            ok, message = validate(xml_text, xsds)
            if not ok:
                failed += 1
                print('FAIL  %s -- %s\n      %s' % (label, what, message))

    print('%d documents checked against the published schemas, %d failed' % (checked, failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
