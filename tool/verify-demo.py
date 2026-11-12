"""Check the saved MP4 container, narration sources and exported metadata."""
from pathlib import Path
import array
import json
import math
import struct
import wave

demo = Path(__file__).resolve().parent.parent / 'demo'
info = json.loads((demo / 'verification.json').read_text(encoding='utf-8'))
data = (demo / 'tapcpeso-demo.mp4').read_bytes()


def boxes(start, end):
    while start + 8 <= end:
        size, kind = struct.unpack_from('>I4s', data, start)
        header = 8
        if size == 1:
            size = struct.unpack_from('>Q', data, start + 8)[0]
            header = 16
        if size == 0:
            size = end - start
        assert size >= header and start + size <= end, 'Invalid or truncated MP4 box'
        yield kind, start + header, start + size
        start += size


def handlers(start, end):
    result = []
    for kind, a, b in boxes(start, end):
        if kind in (b'moov', b'trak', b'mdia'):
            result.extend(handlers(a, b))
        elif kind == b'hdlr':
            result.append(data[a + 8:a + 12].decode('ascii'))
    return result


assert len(data) == info['size'], 'Saved file size differs from rendered blob'
assert data[4:8] == b'ftyp', 'Not an MP4 container'
tracks = handlers(0, len(data))
assert 'vide' in tracks and 'soun' in tracks, 'Missing video or audio track'
assert 59.5 <= info['duration'] <= 61, 'Not approximately one minute'
assert (info['width'], info['height']) == (1280, 720)
levels = []
for file in sorted((demo / 'audio').glob('*.wav')):
    with wave.open(str(file)) as voice:
        assert voice.getsampwidth() == 2
        samples = array.array('h', voice.readframes(voice.getnframes()))
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
    assert rms > 100, f'Silent narration: {file.name}'
    levels.append(round(rms))
assert len(levels) == 8
info.update(saved_file_bytes=len(data), container_tracks=tracks,
            narration_pcm_rms=levels, saved_container_verified=True)
(demo / 'verification.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
print(json.dumps(info, indent=2))
