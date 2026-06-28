#!/usr/bin/env python3
import os
import re
import sys
from pathlib import Path


def main() -> int:
    version = os.environ["VERSION"]
    build = os.environ["BUILD"]
    ed_signature = os.environ["ED_SIGNATURE"]
    length = os.environ["LENGTH"]
    tag = os.environ["TAG"]
    repo = os.environ["REPO"]

    download_url = f"https://github.com/{repo}/releases/download/{tag}/Toast-{version}.zip"
    pub_date = os.popen('LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000"').read().strip()

    item = f"""    <item>
      <title>Version {version}</title>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <pubDate>{pub_date}</pubDate>
      <enclosure
        url="{download_url}"
        length="{length}"
        type="application/octet-stream"
        sparkle:edSignature="{ed_signature}"/>
    </item>
"""

    appcast_path = Path("web/public/appcast.xml")
    content = appcast_path.read_text(encoding="utf-8")

    version_pattern = re.compile(
        r"    <item>\s*"
        r"<title>Version [^<]+</title>.*?<sparkle:shortVersionString>"
        + re.escape(version)
        + r"</sparkle:shortVersionString>.*?</item>\s*",
        re.DOTALL,
    )
    if version_pattern.search(content):
        content = version_pattern.sub(item, content, count=1)
    else:
        channel_close = re.search(r"\n(\s*)</channel>", content)
        if not channel_close:
            print("Invalid appcast.xml: missing channel close tag", file=sys.stderr)
            return 1
        marker = channel_close.group(0)
        content = content.replace(marker, "\n" + item.rstrip() + marker, 1)

    appcast_path.write_text(content, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
