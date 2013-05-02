Fs            = require 'fs'
Path          = require 'path'
Assert        = require 'assert'
{exec, spawn} = require 'child_process'
Async         = require 'async'
Less          = require 'less'
Lessr         = require '../src/lessr'

TEST_OUT     = Path.join __dirname    , "out"

LESS_DIR     = Path.join TEST_OUT     , "less"
LESS_SUB_DIR = Path.join LESS_DIR     , "sub"
CSS_DIR      = Path.join TEST_OUT     , "css"

MAIN_LESS    = Path.join LESS_DIR     , "main.less"
OUTER_LESS   = Path.join LESS_DIR     , "outer.less"
INNER_LESS   = Path.join LESS_SUB_DIR , "inner.less"
MAIN_CSS     = Path.join CSS_DIR      , "main.css"
NON_LESS     = Path.join LESS_DIR     , "non_less"

# enlarge this value if test fails due to host performance
DELAY        = process.env.DELAY ? 300

# the running Lessr
RUNNER       = null

CODES =
    main: """
        @import "outer.less";"""

    outer: """
        @base: #f938ab;

        .box-shadow(@style, @c) when (iscolor(@c)) {
          box-shadow:         @style @c;
          -webkit-box-shadow: @style @c;
          -moz-box-shadow:    @style @c;
        }
        .box-shadow(@style, @alpha: 50%) when (isnumber(@alpha)) {
          .box-shadow(@style, rgba(0, 0, 0, @alpha));
        }
        .box { 
          color: saturate(@base, 5%);
          border-color: lighten(@base, 30%);
          div { .box-shadow(0 0 5px, 30%) }
        }"""

    inner: """
        @color: #4D926F;

        #header {
          color: @color;
        }
        h2 {
          color: @color;
        }"""

    updated_main: """
        @import "outer.less";
        @import "sub/inner.less";"""

    updated_inner: """
        @color: #FFFF00;

        h1, h2, h3, h4 {
          color: @color;
        }"""

wait = (milliseconds, func) -> setTimeout func, milliseconds

# init test space
setup = (next) ->

    # create a tree structure like this:
    #
    # <ROOT>
    #  |-- less
    #  |    |-- main.less
    #  |    |-- outer.less
    #  |    \-- sub
    #  |         \-- inner.less
    #  +-- css

    exec "mkdir -p #{LESS_DIR} #{CSS_DIR}", (err) ->
        next err if err

        Async.parallel [
            # create less/main.less
            (callback) ->
                Fs.writeFile MAIN_LESS, CODES.main, callback

            # create less/outer.less
            (callback) ->
                Fs.writeFile OUTER_LESS, CODES.outer, callback

        ], (err) ->
            next err if err

            # start watching
            opts =
                output   : CSS_DIR
                compress : yes
                watch    : LESS_DIR
            RUNNER = Lessr.compile MAIN_LESS, opts

            next null

# destroy test space 
clean = (next) ->
    spawn("rm", ["-rf", TEST_OUT], {stdio: "inherit"}).on "exit", (status) ->
        next null

describe "Lessr", ->
    before setup
    after clean

    it "should compile .less files while start watching", (done) ->
        this.timeout 2 * DELAY
        wait DELAY, ->
            # check compiled main.css file
            Async.waterfall [
                # read main.css
                (next) ->
                    Fs.readFile MAIN_CSS, next

                # compile code of main.less
                (main_css, next) ->
                    opts =
                        compress: yes
                        paths: [Path.dirname MAIN_LESS]
                    Less.render CODES.main, opts, (err, expected) ->
                        next err if err
                        Assert.equal main_css, expected
                        next null

            ], (err) ->
                done err

    it "should compile/watch new .less files", (done) ->
        this.timeout 3 * DELAY

        Async.waterfall [
            # make sure dir tree exists
            (next) ->
                exec "mkdir -p #{LESS_SUB_DIR}", (err) ->
                    wait DELAY, ->
                        next err

            # create new .less file
            (next) ->
                Fs.writeFile INNER_LESS, CODES.inner, (err) ->
                    # wait for Lessr to work
                    wait DELAY, ->
                        next err

            # check RUNNER.SOURCES["watch"]
            (next) ->
                Assert.notEqual RUNNER.SOURCES["watch"].indexOf INNER_LESS, -1
                next null

        ], (err) ->
            done err

    it "should re-compile when main.less is modified", (done) ->
        this.timeout 2 * DELAY

        Async.waterfall [
            # update main.less
            (next) ->
                Fs.writeFile MAIN_LESS, CODES.updated_main, (err) ->
                    wait DELAY, ->
                        next err

            # check main.css
            (next) ->
                Async.parallel {
                    compiled: (next) ->
                        Fs.readFile MAIN_CSS, next

                    expected: (next) ->
                        opts =
                            compress: yes
                            paths: [Path.dirname MAIN_LESS]
                        Less.render CODES.updated_main, opts, next

                }, (err, results) ->
                    Assert.equal results.compiled.toString(), results.expected
                    next err

        ], (err) ->
            done err

    it "should re-compile main.less when inner.less is modified", (done) ->
        this.timeout 2 * DELAY

        Async.waterfall [
            # update inner.less
            (next) ->
                Fs.writeFile INNER_LESS, CODES.updated_inner, (err) ->
                    wait DELAY, ->
                        next err

            # check main.css
            (next) ->
                Async.parallel {
                    compiled: (next) ->
                        Fs.readFile MAIN_CSS, next

                    expected: (next) ->
                        opts =
                            compress: yes
                            paths: [Path.dirname MAIN_LESS]
                        Less.render CODES.updated_main, opts, next

                }, (err, results) ->
                    Assert.equal results.compiled.toString(), results.expected
                    next err

        ], (err) ->
            done err

    it "should ignore non .less file", (done) ->
        this.timeout 2 * DELAY

        Async.series [
            # create a dummy file
            (next) ->
                Fs.writeFile NON_LESS, "", (err) ->
                    wait DELAY, ->
                        next err

            # check RUNNER.SOURCES.ignore
            (next) ->
                Assert.ok RUNNER.SOURCES.ignore[NON_LESS]
                next null

        ], (err) ->
            done err

    it "should remove the .css file when corresponding .less file is deleted", (done) ->
        this.timeout 2 * DELAY

        Async.waterfall [
            # remove main.less file
            (next) ->
                Fs.unlink MAIN_LESS, (err) ->
                    # wait for Lessr to work
                    wait DELAY, ->
                        next err

            # check main.css file
            (next) ->
                Fs.exists MAIN_CSS, (exists) ->
                    Assert.ok not exists
                    next null

        ], (err) ->
            done err
