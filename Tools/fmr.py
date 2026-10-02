"""Reads the compact region files (.fmr) made by Tools/build_regions.py."""
import struct
import zlib


def read_fmr(path):
    """Yields (code, name, [polygon as list of rings of (lon, lat)])."""
    data = zlib.decompress(open(path, "rb").read(), -15)
    assert data[:4] == b"FMR1"
    count = struct.unpack_from("<I", data, 4)[0]
    i = 8
    lat = lon = 0

    def varint():
        nonlocal i
        result = shift = 0
        while True:
            b = data[i]
            i += 1
            result |= (b & 0x7F) << shift
            if not b & 0x80:
                return result
            shift += 7

    def zigzag():
        n = varint()
        return (n >> 1) ^ -(n & 1)

    for _ in range(count):
        n = data[i]; i += 1
        code = data[i:i + n].decode(); i += n
        n = struct.unpack_from("<H", data, i)[0]; i += 2
        name = data[i:i + n].decode(); i += n
        polys = []
        for _ in range(varint()):
            rings = []
            for _ in range(varint()):
                ring = []
                for _ in range(varint()):
                    lat += zigzag()
                    lon += zigzag()
                    ring.append((lon / 1e5, lat / 1e5))
                rings.append(ring)
            polys.append(rings)
        yield code, name, polys
