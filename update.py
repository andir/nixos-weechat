#! /usr/bin/env nix-shell
#! nix-shell -i python -p python3 -p git -p nix

from urllib.request import urlopen
from urllib.parse import urlunparse, urlparse
from xml.dom.minidom import parse, parseString
import json
import subprocess
import hashlib

commit_hash = subprocess.check_output(['git', 'ls-remote', 'git://github.com/weechat/scripts.git', 'master']).decode('utf-8').split('\t')[0]
r = urlopen('https://weechat.org/files/plugins.xml')
dom = parseString(r.read())

def element_text(element, tag):
    return element.getElementsByTagName(tag)[0].childNodes[0].nodeValue


def prefetch(url, sha512):
    subprocess.check_output(['nix-prefetch-url', '--type', 'sha512', url, sha512])
    return True

def mkRawGithubUrl(language, url):
    url = urlparse(url)
    filename = url.path.split('/')[-1]

    path = 'weechat/scripts/raw/{commit_hash}/{language}/{filename}'.format(
        commit_hash=commit_hash,
        language=language,
        filename=filename,
    )

    return urlunparse(('https', 'github.com', path, '', '', ''))

def mkPlugin(element):
    d = dict(
            name=element_text(element, "name"),
            language=element_text(element, "language"),
            version=element_text(element, "version"),
            license=element_text(element, "license"),
            description=element_text(element, "desc_en"),
            url=element_text(element, "url"),
            md5sum=element_text(element, "md5sum"),
            sha512=element_text(element, "sha512sum"),
    )

    gh_url = mkRawGithubUrl(d['language'], d['url'])
    d['gh_url'] = gh_url

    # prefetch the files to verify that the checksums fit
    prefetch(gh_url, d['sha512'])

    return {d["name"]: d}

plugins = {}
for plugin in dom.getElementsByTagName('plugin'):
    p = mkPlugin(plugin)
    plugins.update(**p)

print(json.dumps(plugins))
