import os
import re

dir_path = r'C:\Users\nekol\desktop\istqm_framework\k_dev\huli-kamote\hulikamote_visualizer\lib\widgets\visualizers'

for root, dirs, files in os.walk(dir_path):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            # Fix textAlign inside TextStyle
            # Pattern: style: TextStyle(..., textAlign: TextAlign.center) -> style: TextStyle(...), textAlign: TextAlign.center
            # Let's use regex. It might be tricky if it's over multiple lines, but usually I wrote it as:
            # style: TextStyle(color: Colors.red[800], fontSize: 12, textAlign: TextAlign.center)
            
            # Simple regex replace for the specific single-line occurrences
            # Match: style: TextStyle([^)]*),\s*textAlign:\s*TextAlign\.center\s*\)
            # Actually, `textAlign` might be at the end of the TextStyle parameters.
            # Let's just look for: `, textAlign: TextAlign.center` inside TextStyle and move it out.
            # e.g. Text("...", style: TextStyle(color: C, fontSize: 12, textAlign: TextAlign.center))
            # becomes Text("...", style: TextStyle(color: C, fontSize: 12), textAlign: TextAlign.center)
            
            new_content = re.sub(
                r'style:\s*TextStyle\((.*?),\s*textAlign:\s*TextAlign\.center\s*\)',
                r'style: TextStyle(\1), textAlign: TextAlign.center',
                content,
                flags=re.DOTALL
            )
            
            # Also fix `textAlign: TextAlign.center` if it's the only param (unlikely, but just in case)
            new_content = re.sub(
                r'style:\s*TextStyle\(\s*textAlign:\s*TextAlign\.center\s*\)',
                r'textAlign: TextAlign.center',
                new_content,
                flags=re.DOTALL
            )

            # Fix swerving_visualizer.dart math.cos
            if file == 'swerving_visualizer.dart':
                new_content = new_content.replace('(t * 3.14159).cos()', 'math.cos(t * 3.14159)')

            if content != new_content:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                print(f"Fixed {file}")

print("Done")
