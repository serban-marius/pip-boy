#!/usr/bin/env python3
# Remove whole methods (with their attributes and docblock) from a PHP class, in place.
# usage: rm_php_methods.py <file.php> <methodName>... ; exits non-zero if a name is not found.
import re, sys
path, names = sys.argv[1], sys.argv[2:]
lines = open(path).read().split('\n')
for name in names:
    idx = next((i for i, l in enumerate(lines) if re.search(r'function ' + re.escape(name) + r'\(', l)), None)
    if idx is None:
        sys.exit(f'not found: {name}')
    start = idx
    while start > 0 and re.match(r'\s{4}(#\[|/\*\*|\*|\*/)|\s{5}\*', lines[start-1]):
        start -= 1
    end = next(i for i in range(idx, len(lines)) if lines[i] == '    }')
    # drop the blank line after
    if end + 1 < len(lines) and lines[end+1] == '':
        end += 1
    del lines[start:end+1]
open(path, 'w').write('\n'.join(lines))
