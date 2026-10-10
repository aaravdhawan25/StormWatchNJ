"""Municipal email domains allowed to hold a township account.

The list was supplied by the project owner and has not been independently
checked against each municipality. Review it before real use — a wrong entry
here would let the holder of some other organisation's mailbox act as a town.

Matching is on the exact domain after the last "@". Suffix or substring matching
would be a hole: "someone@princetonnj.gov.example.com" and
"someone@notprincetonnj.gov" must both fail.

A matching domain is necessary but never sufficient. An account only becomes a
township account once its owner has proved they receive mail at the address
(see auth.py), because anyone can type someone else's email into a form.
"""

TOWNSHIP_DOMAINS = {
    # Mercer County
    "ewingnj.org": ("Ewing Township", "Mercer"),
    "hopewellboro-nj.us": ("Hopewell Borough", "Mercer"),
    "hopewelltwp.org": ("Hopewell Township", "Mercer"),
    "penningtonboro.org": ("Pennington Borough", "Mercer"),
    "princetonnj.gov": ("Princeton", "Mercer"),
    "trentonnj.org": ("Trenton", "Mercer"),
    "westwindsortwp.com": ("West Windsor Township", "Mercer"),
    # Middlesex County
    "cranbury-nj.com": ("Cranbury Township", "Middlesex"),
    "dunellen-nj.gov": ("Dunellen Borough", "Middlesex"),
    "eastbrunswick.org": ("East Brunswick Township", "Middlesex"),
    "oldbridge.com": ("Old Bridge Township", "Middlesex"),
    "plainsboronj.com": ("Plainsboro Township", "Middlesex"),
    "sbtnj.net": ("South Brunswick Township", "Middlesex"),
    "southrivernj.org": ("South River Borough", "Middlesex"),
    "spotswoodboro.com": ("Spotswood Borough", "Middlesex"),
    # Somerset County
    "boundbrook-nj.org": ("Bound Brook Borough", "Somerset"),
    "bridgewaternj.gov": ("Bridgewater Township", "Somerset"),
    "franklintwpnj.org": ("Franklin Township", "Somerset"),
    # Union County
    "plainfieldnj.gov": ("Plainfield", "Union"),
}


def domain_of(email):
    return email.rsplit("@", 1)[-1].strip().lower() if "@" in email else ""


def township_for(email):
    """(name, county) if the address is on a recognised municipal domain."""
    return TOWNSHIP_DOMAINS.get(domain_of(email))
