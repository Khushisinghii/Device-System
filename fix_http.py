import os
import re

base_dir = r'C:\Users\vv646\go_go\lib'

for root, dirs, files in os.walk(base_dir):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            if 'await http' in content:
                # Replace "await http\s*\.\s*get" with "await ApiService.get"
                content = re.sub(r'await\s+http\s*\.\s*get', 'await ApiService.get', content)
                content = re.sub(r'await\s+http\s*\.\s*post', 'await ApiService.post', content)
                content = re.sub(r'await\s+http\s*\.\s*put', 'await ApiService.put', content)
                content = re.sub(r'await\s+http\s*\.\s*delete', 'await ApiService.delete', content)

                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)

print("Fixed remaining http calls")
