"""
lan_address.py - this laptop's address on the Wi-Fi, hotspot or cable it is connected to (works without internet).
A phone on the same network reaches the backend at that address.
"""
import ipaddress
import socket


def lan_ips() -> list[str]:
    """Private IPv4 addresses of this laptop, without loopback and without 169.254.x.x (an unconnected adapter)."""
    try:
        import psutil
        found = [a.address for addrs in psutil.net_if_addrs().values() for a in addrs if a.family == socket.AF_INET]
    except ImportError:
        try:
            found = [info[4][0] for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)]
        except OSError:
            found = []
    usable = []
    for ip in dict.fromkeys(found):
        address = ipaddress.ip_address(ip)
        if address.is_private and not address.is_loopback and not address.is_link_local:
            usable.append(ip)
    return usable
