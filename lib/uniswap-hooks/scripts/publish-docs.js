const proc = require('child_process');

const run = cmd => {
    proc.execSync(cmd, { stdio: 'inherit' });
};

run('npm run prepare-docs');
run('git add -f docs');  // --force needed because generated docs files are gitignored

run('git commit -m "Update docs"');