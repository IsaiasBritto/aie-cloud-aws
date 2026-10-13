import feedparser
import requests
import json
import uuid

feed_url = "https://podcasts.files.bbci.co.uk/p09qw1cn.rss"
feed = feedparser.parse(feed_url)

episode = feed.entries[0]
mp3 = episode.enclosures[0].href

print("Título :", episode.title)
print("MP3    :", mp3)

radical = str(uuid.uuid4())
mp3_file = f"{radical}.mp3"
json_file = f"{radical}.json"

r = requests.get(mp3)
with open(mp3_file, "wb") as f:
    f.write(r.content)

with open(json_file, "w", encoding="utf-8") as f:
    json.dump(episode, f, ensure_ascii=False, indent=4)