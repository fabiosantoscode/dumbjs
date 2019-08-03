# dumbjs

[![Build Status](https://travis-ci.org/fabiosantoscode/dumbjs.svg?branch=master)](https://travis-ci.org/fabiosantoscode/dumbjs)

WIP: Parts of this repo don't work properly yet. If something is crashing dumbjs and it doesn't seem like an intentional dumbjs-originated limitation, file an issue!

A first pass for js2cpp. Uses browserify's dependencies to flatten the dependency tree into a single file, then makes the file not use closures at all by implementing closures in pure javascript.

This was created because I found it too hard to implement closures in js2cpp, then it became clear that it would be much better to implement them at the javascript level, and make the current js2cpp just work on a simple subset of javascript.

So I made dumbjs. It turns javascript into a simpler subset of itself. The most important transformations:

 * Make the compiled javascript work in an environment without closures
 * Flatten the dependency tree like browserify does, turning it into a single file so js2cpp doesn't need to care about more than one file.
 * Without any name collisions, unwrap functions so as to leave no nested function.
 * Separate definitions from declarations, so that var x = 3 in the global scope becomes var x; x = 3, then put every statement that performs any action (assignment or function call) in the global scope, in order, in a single function called "main", whose last statement will be "return 0".


# How to install and run

Installation is simply `npm install dumbjs -g`

Running it is as easy as `dumbjs < input.js > output.dumb.js`

There are currently no command line options :(


# API docs

## `require('dumbjs')(javascriptCode, [options])`

Dumbify a javascript string and return the resulting javascript code as a string.

## `require('dumbjs').dumbifyAST(javascriptAST, [options])`

Dumbify a parsed javascript AST as returned by `esprima`, `acorn` or whatever parser you prefer.

## `options`

The options you can pass are written down in dumbifyAST, which is a pretty straightforward function in the `index` file.

They turn several passes on and off, and these passes are not documented as of yet :P


# What do I need to run dumbified code?

So you want to transplile javascript to something huh? That sounds like fun!

You have to implement some functions in your target environment!


## BIND(func, closure) -> functionBoundToClosure

In plain javascript: `function BIND(func,closure){return func.bind(null, closure)}`

This function takes a function and an object, and returns a function that takes that object as the first argument. Simple right? A single-argument curry. This is used to pass closures in environments that don't have them.

For js2cpp, for example, I had to turn every function that `BIND` was called on (these functions take `_closure` as the first argument so they're easy to find), into a callable class, and turn all `BIND` calls into `new ThatCallableClass(theClosure)`.


## JS_ADD(a, b) -> Number|String

In plain javascript: `function JS_ADD(a, b) { return a + b }`

When trying to do type conversions, if the type of `a` and/or `b` is not known at compile time, `a + b` turns into `JS_ADD(a, b)`. This is because it is not clear whether to concatenate `a` and `b` as strings ( `String(a) + String(b)`) or to convert them to numbers and add their values ( `Number(a) + Number(b)` ), as this depends on dumbjs being privvy of both types!

They can be stactically removed if there is enough knowledge about the types (maybe dumbjs didn't know of some function's existence), or you can use the `typeof` operator's equivalent to know what kind of variable it is, and perform the addition or concatenation.

This is specified in great detail in the [spec](https://tc39.github.io/ecma262/#sec-addition-operator-plus-runtime-semantics-evaluation). Make sure to read into the toPrimitive part, it becomes super unpredictable if the object has a toString or valueOf method. They are both used, and they don't need to return strings ;)

# Recommended reading

[This document](http://dspace.mit.edu/bitstream/handle/1721.1/5854/AIM-199.pdf) has been invaluable in understanding the difficulties and nuances of implementing closures, and describes complicated problems in a way that's easily understandable.

[This wikipedia article](https://en.wikipedia.org/wiki/Funarg_problem) describes the main problem of implementing closures, and why you can't store functions and their closures on the stack if you want functions in your language to be first-class.
