// Invoke the platform binary directly: the 1.7.1 npm wrapper drops nonzero exit codes.
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
const require = createRequire(import.meta.url);
const [tool,...args] = process.argv.slice(2);
if (!['forge','anvil'].includes(tool)) throw new Error('Expected forge or anvil');
const arch = process.arch === 'x64' ? 'amd64' : process.arch;
const binary = require.resolve(`@foundry-rs/${tool}-${process.platform}-${arch}/bin/${tool}`);
const child = spawn(binary,args,{stdio:'inherit'});
child.on('error',e=>{console.error(e);process.exitCode=1;});
child.on('exit',(code,signal)=>{process.exitCode=code??1;});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>child.kill(signal));
