import re

# Update login_page.dart
with open(r'C:\Users\vv646\go_go\lib\pages\auth\login_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_content = content.replace(
    'if (json["status"] == true) {',
    'if (json["status"] == true) {\n                                  if (json["token"] != null) {\n                                    await prefs.setString("jwt_token", json["token"]);\n                                  }'
)
with open(r'C:\Users\vv646\go_go\lib\pages\auth\login_page.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)

# Update signup_page.dart
with open(r'C:\Users\vv646\go_go\lib\pages\auth\signup_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_content = content.replace(
    'if (json["status"] == true) {',
    'if (json["status"] == true) {\n                                final prefs = await SharedPreferences.getInstance();\n                                if (json["token"] != null) {\n                                  await prefs.setString("jwt_token", json["token"]);\n                                }'
)
with open(r'C:\Users\vv646\go_go\lib\pages\auth\signup_page.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Auth pages updated")
