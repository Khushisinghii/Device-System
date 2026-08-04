import os
import re

base_dir = r'C:\Users\vv646\go_go\lib'

for root, dirs, files in os.walk(base_dir):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            # Skip api_service.dart itself
            if 'api_service.dart' in filepath:
                continue

            if 'http.' in content or 'package:http/http.dart' in content:
                # Calculate relative path to core/services/api_service.dart
                rel_path_from_lib = os.path.relpath(filepath, base_dir).replace('\\', '/')
                depth = rel_path_from_lib.count('/')
                if depth == 0:
                    api_import = "import 'core/services/api_service.dart';"
                else:
                    api_import = "import '" + '../' * depth + "core/services/api_service.dart';"
                
                # Replace import
                content = re.sub(r"import\s+['\"]package:http/http\.dart['\"]\s+as\s+http;", api_import, content)
                
                # Replace http calls
                content = content.replace('http.get', 'ApiService.get')
                content = content.replace('http.post', 'ApiService.post')
                content = content.replace('http.put', 'ApiService.put')
                content = content.replace('http.delete', 'ApiService.delete')
                
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(content)

print("All dart files updated to use ApiService")
