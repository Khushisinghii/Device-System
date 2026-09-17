import os
import re

base_dir = r'C:\Users\vv646\go_go\lib'
new_url = 'https://galleries-symphony-euros-addressing.trycloudflare.com'

# Regex to match any old cloudflare url (e.g. https://pharmacy-although... or https://genetics-ports...)
url_pattern = re.compile(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com')

for root, dirs, files in os.walk(base_dir):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            if url_pattern.search(content):
                new_content = url_pattern.sub(new_url, content)
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)

print("Updated all Cloudflare URLs successfully!")
