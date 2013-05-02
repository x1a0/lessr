# Lessr - less watcher and compiler.

[![Build Status](https://travis-ci.org/zhangxiao/lessr.png)](https://travis-ci.org/zhangxiao/lessr)

Lessr provides an API for watching and compiling less files to css files.

You can install it via `npm install lessr` and simply use it by `require('lessr').watch(src, opts)`. Available options are:

* `output` Specify base path for saving the generated css files. If not given, css file will be sitting next to corresponding less file.

* `compress` Set to `true` if you want to compress the css codes (doesn't mean combined).

* `watch` Specify paths you want to watch and when they change it automatically re-compiles sources.

A full example would be like:

    var lessr = require('lessr');

    lessr.watch("/path/to/less", {
        output: "/path/to/css",
        compress: true,
        watch: ["/path/to/less/a", "/path/to/less/b"]
    });

    console.log("start watching and compiling less files...");
