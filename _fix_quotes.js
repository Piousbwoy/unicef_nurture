const fs = require('fs');

function fixFile(path) {
  let lines = fs.readFileSync(path, 'utf8').split('\n');
  let changed = false;
  
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    const match = line.match(/^(\s*)'(.+)'(,?\s*)$/);
    if (match) {
      const indent = match[1];
      const content = match[2];
      const trailing = match[3];
      if (content.includes("'")) {
        const escaped = content.replace(/"/g, '\\"');
        lines[i] = indent + '"' + escaped + '"' + trailing;
        changed = true;
      }
    }
  }
  
  if (changed) {
    fs.writeFileSync(path, lines.join('\n'), 'utf8');
    console.log('Fixed: ' + path);
  } else {
    console.log('Clean: ' + path);
  }
}

const files = [
  'lib/presentation/caregiver/growth/grow_play_tab.dart',
  'lib/presentation/caregiver/family/family_tab.dart',
  'lib/presentation/caregiver/care_plan/care_plan_tab.dart',
  'lib/presentation/caregiver/help/help_tab.dart',
];
files.forEach(fixFile);
