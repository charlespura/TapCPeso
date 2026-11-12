"""Export the video's narration as a matching transcript and SRT subtitles."""
import json
from pathlib import Path

demo = Path(__file__).resolve().parent.parent / 'demo'
scenes = json.loads((demo / 'storyboard.json').read_text(encoding='utf-8'))


def stamp(seconds):
    milliseconds = round(seconds * 1000)
    return f'{milliseconds // 3600000:02}:{milliseconds // 60000 % 60:02}:{milliseconds // 1000 % 60:02},{milliseconds % 1000:03}'


subtitles = '\n\n'.join(f'{i + 1}\n{stamp(s["start"])} --> {stamp(s["end"])}\n{s["narration"]}'
                         for i, s in enumerate(scenes))
(demo / 'tapcpeso-demo.srt').write_text(subtitles + '\n', encoding='utf-8')
transcript = '\n\n'.join(f'{s["start"]:02}–{s["end"]:02} seconds / {s["chapter"]}\n{s["narration"]}'
                          for s in scenes)
(demo / 'transcript.txt').write_text(transcript + '\n', encoding='utf-8')
