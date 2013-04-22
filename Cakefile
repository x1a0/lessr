WINDOWS = process.platform.indexOf('win') is 0
NODE    = process.execPath
NPM     = if WINDOWS then process.execPath.replace('node.exe','npm.cmd') else 'npm'
EXT     = (if WINDOWS then '.cmd' else '')
APP     = process.cwd()
TESTS   = "#{APP}/src/tests"
BIN     = "#{APP}/node_modules/.bin"
CAKE    = "#{BIN}/cake#{EXT}"
COFFEE  = "#{BIN}/coffee#{EXT}"
MOCHA   = "#{BIN}/mocha#{EXT}"
OUT     = "#{APP}/out"
SRC     = "#{APP}/src"

Path = require 'path'
{spawn} = require 'child_process'

done = (err) ->
    console.log "Done!"


# remove all non-revisioned objects
cleanall = (next) ->
    cmd = "rm"
    args = ["-rf", OUT, Path.join(APP, "node_modules"), Path.join(SRC, "tests", "run")]
    spawn(cmd, args, {stdio: "inherit", cwd: APP}).on "exit", next

task "cleanall", "clean up everything!", ->
    cleanall done

# remove compiled javascript
clean = (next) ->
    cmd = "rm"
    args = ["-rf", OUT]
    spawn(cmd, args, {stdio: "inherit", cwd: APP}).on "exit", next

task "clean", "clean up", ->
    clean done


# compile coffee-script to javascript
compile = (next) ->
	spawn(COFFEE, ["-bco", OUT, SRC], {stdio: "inherit", cwd: APP}).on "exit", next

task "compile", "compile coffee-script to javascript", ->
    compile done


# run tests
test = (next) ->
    spawn(MOCHA, ["--compilers", "coffee:coffee-script", TESTS], {stdio: "inherit", cwd: APP}).on "exit", next

task "test", "run tests", ->
    test done
