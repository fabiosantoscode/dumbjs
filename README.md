# dumbjs

A first pass for js2cpp. Uses browserify's dependencies to flatten the dependency tree into a single file, then makes the file not use closures at all by implementing closures in pure javascript.

This was created because I found it too hard to implement closures in js2cpp, then it became clear that it would be much better to implement them at the javascript level, and make the current js2cpp just work on a simple subset of javascript.

So I made dumbjs. It turns javascript into a simpler subset of itself. The most important transformations:

 * Make the compiled javascript work in an environment without closures
 * Flatten the dependency tree like browserify does, turning it into a single file so js2cpp doesn't need to care about more than one file.
 * Without any name collisions, unwrap functions so as to leave no nested function.
 * Separate definitions from declarations, so that var x = 3 in the global scope becomes var x; x = 3, then put every statement that performs any action (assignment or function call) in the global scope, in order, in a single function called "main", whose last statement will be "return 0".

# Recommended reading

[This document](http://dspace.mit.edu/bitstream/handle/1721.1/5854/AIM-199.pdf) has been invaluable in understanding the difficulties and nuances of implementing closures, and describes complicated problems in a way that's easily understandable.

[This wikipedia article](https://en.wikipedia.org/wiki/Funarg_problem) describes the main problem of implementing closures, and why you can't store functions and their closures on the stack if you want functions in your language to be first-class.
