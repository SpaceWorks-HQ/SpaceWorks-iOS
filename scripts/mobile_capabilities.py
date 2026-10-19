"""Validate optional owner capabilities; missing configuration never invents a server domain."""
import re
import ipaddress


def capabilities(brand, mode):
    if mode not in ("Debug", "Release"):
        raise ValueError("Unknown build configuration")
    apns = brand.get("aps_environment")
    if apns not in (None, "production"):
        raise ValueError("aps_environment must be production or null; Debug uses development automatically")
    domains = brand.get("associated_domains", [])
    if not isinstance(domains, list) or len(domains) > 20 or not all(isinstance(value, str) for value in domains) or len(set(domains)) != len(domains):
        raise ValueError("associated_domains must be a unique list of at most 20 explicit domains")
    for entry in domains:
        if not isinstance(entry, str) or ":" not in entry:
            raise ValueError("Invalid associated domain")
        service, hostname = entry.split(":", 1)
        try:
            ipaddress.ip_address(hostname)
        except ValueError:
            pass
        else:
            raise ValueError("Associated domains require an explicit DNS hostname")
        labels = hostname.split(".")
        if service not in ("applinks", "webcredentials") or len(hostname) > 253 or len(labels) < 2 or not all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label) for label in labels):
            raise ValueError("Use an explicit applinks: or webcredentials: DNS hostname without URL, port, wildcard or path")
    if (apns is not None or domains) and not re.fullmatch(r"[A-Z0-9]{10}", brand.get("ios_team_id", "")):
        raise ValueError("Configure the actual ten-character ios_team_id before enabling Apple capabilities")
    result = {}
    if apns is not None:
        result["aps-environment"] = "development" if mode == "Debug" else "production"
    if domains:
        result["com.apple.developer.associated-domains"] = domains
    return result
