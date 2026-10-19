"""Validate owner-provided legal/help links and generate nullable native constants.

These values are external navigation destinations, never API deployment origins.
Missing configuration remains unavailable; no URL or credentials are inferred.
"""
import ipaddress
import re
import unicodedata
from urllib.parse import urlsplit, urlunsplit


def optional_https_url(value, field):
    if value is None:
        return None
    if not isinstance(value, str) or not value or any(
        character.isspace() or unicodedata.category(character).startswith('C') or character == '\\'
        for character in value
    ) or any(character in value for character in '\"<>^`{}|') or re.search(r'%(?![0-9A-Fa-f]{2})', value):
        raise ValueError(f'{field} must be null or an absolute HTTPS URL without whitespace or controls')
    try:
        parsed = urlsplit(value)
        hostname = parsed.hostname
        _ = parsed.port  # Invalid/non-numeric/out-of-range ports must fail validation.
        if (parsed.scheme.lower() != 'https' or not parsed.netloc or not hostname
                or parsed.username is not None or parsed.password is not None
                or '@' in parsed.netloc or parsed.netloc.endswith(':')):
            raise ValueError('invalid HTTPS authority')
        try:
            address = ipaddress.ip_address(hostname)
            normalized_host = '[' + hostname.lower() + ']' if address.version == 6 else hostname
        except ValueError:
            normalized_host = hostname.encode('idna').decode('ascii').lower()
            if len(normalized_host.rstrip('.')) > 253 or not all(
                re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', label)
                for label in normalized_host.rstrip('.').split('.')
            ):
                raise ValueError('invalid hostname')
        if '[' in parsed.path or ']' in parsed.path or '#' in parsed.fragment:
            raise ValueError('invalid URI component')
        if parsed.netloc.startswith('['):
            port_suffix = parsed.netloc[parsed.netloc.index(']') + 1:]
        else:
            port_suffix = ':' + parsed.netloc.rsplit(':', 1)[1] if ':' in parsed.netloc else ''
        normalized = urlunsplit(('https', normalized_host + port_suffix, parsed.path, parsed.query, parsed.fragment))
    except (ValueError, UnicodeError):
        # Errors identify the field without echoing owner URLs or credentials.
        raise ValueError(f'{field} must be null or an absolute HTTPS URL without credentials') from None
    return normalized



def validated_links(brand):
    return {key: optional_https_url(brand.get(key), key) for key in ('support_url', 'privacy_url')}
