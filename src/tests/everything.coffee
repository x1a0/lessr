Fs            = require 'fs'
Path          = require 'path'
Assert        = require 'assert'
{exec, spawn} = require 'child_process'
Async         = require 'async'
Less          = require 'less'
Lessr         = require '../lib/lessr'

EXAMPLE_LESS = Path.join __dirname, "example.less"
SPACE        = Path.join __dirname, "out"
LESS_DIR     = Path.join SPACE, "less"
LESS_FILE    = Path.join LESS_DIR, "sub", "test.less"
CSS_DIR      = Path.join SPACE, "css"
CSS_FILE     = Path.join CSS_DIR, "sub", "test.css"

# enlarge this value if test fails due to host performance
DELAY        = process.env.DELAY ? 200

wait = (milliseconds, func) -> setTimeout func, milliseconds

# init test space
setup = (next) ->
    exec "mkdir -p #{LESS_DIR}", (err) ->
        next err if err

        # start watching
        Lessr.watch LESS_DIR, {output: CSS_DIR, compress: yes}
        next null

# destroy test space 
clean = (next) ->
    spawn("rm", ["-rf", SPACE], {stdio: "inherit"}).on "exit", (status) ->
        next null

describe "Lessr", ->
    before setup
    after clean

    it "should compile new .less files", (done) ->
        this.timeout 3 * DELAY

        Async.waterfall [
            # make sure dir tree exists
            (next) ->
                exec "mkdir -p #{Path.dirname LESS_FILE}", (err) ->
                    wait DELAY, ->
                        next err

            # create new .less file
            (next) ->
                Fs.writeFile LESS_FILE, "", (err) ->
                    # wait for Lessr to work
                    wait DELAY, ->
                        next err

            # check compiled .css file
            (next) ->
                Fs.exists CSS_FILE, (exists) ->
                    Fs.readdir Path.dirname(CSS_FILE), (err, files) ->
                        Assert.ok exists, "Could't find compiled css file #{CSS_FILE}"
                        next null

        ], (err) ->
            done err

    it "should re-compile if .less files are modified", (done) ->
        this.timeout 2 * DELAY

        Async.waterfall [
            # load example.less
            (next) ->
                Fs.readFile EXAMPLE_LESS, next

            # append less codes to .less file created previously meanwhile compile them
            (data, next) ->
                Async.parallel {
                    append: (next) ->
                        Fs.appendFile LESS_FILE, data.toString(), (err) ->
                            # wait for Lessr to work
                            wait DELAY, ->
                                next err

                    less: (next) ->
                        Less.render data.toString(), {compress: yes}, next

                }, (err, results) ->
                    next err, results.less

            # check re-compiled .css file
            (expected, next) ->
                Fs.readFile CSS_FILE, (err, actual) ->
                    next err, actual.toString(), expected

            (actual, expected, next) ->
                Assert.equal actual, expected
                next null

        ], (err) ->
            done err

    it "should remove the .css file if corresponding .less file is deleted", (done) ->
        this.timeout 2 * DELAY

        Async.waterfall [
            # remove .less file
            (next) ->
                Fs.unlink LESS_FILE, (err) ->
                    # wait for Lessr to work
                    wait DELAY, ->
                        next err

            # check .css file
            (next) ->
                Fs.exists CSS_FILE, (exists) ->
                    Assert.ok not exists
                    next null

        ], (err) ->
            done err
