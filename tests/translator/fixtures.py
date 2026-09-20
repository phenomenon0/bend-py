"""Labeled translator fixtures: written for the judge, not taken from a real module.

`first_dash` exercises what `repo_of` does not: `break` (the Step fold) and the
restricted doctest adapter. Two of its doctests are closed literal calls and
become checked laws; the other two are outside the restriction on purpose.
"""


def first_dash(xs: list[str]) -> str | None:
    """The first item that starts with a dash.

    >>> first_dash(['a', '-b', '-c'])
    '-b'
    >>> first_dash([])
    >>> first_dash(['a', 'b']) is None
    True
    >>> first_dash(sorted(['-z', '-a']))
    '-a'
    """
    hit = None
    for x in xs:
        if x.startswith('-'):
            hit = x
            break
    return hit
