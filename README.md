# Roblox small tester

A small and type checked unit testing framework for Roblox. This library was primarily made as an exercise a few months ago.

## Installation

Copy the contents of **src/Tester.lua** in a ModuleScript under your test directory. Alternatively:

* Download the file **RobloxSmallTester.rbxmx** under **Releases**
* In Roblox Studio, right-click on your test directory (e.g. ReplicatedStorage)
* Select **Insert** -> **Import Roblox Model**
* Browse to **Tester.rbxmx** and select **Open**

## Main features

* Easily readable output with `PrintResultsDefault()`,
* Write your own output with `GetResults()` and `GetModulesInfo()`,
* Create tests using expect nodes with `TestEnvironment.Expect(value: any)`, followed by a validation check with the `TestEnvironment.To[...]` methods,
* Add descriptions and group expect nodes using detail nodes with `TestEnvironment.Detail(message: string, callback: () -> ())`,
* Add to-do messages with `TestEnvironment.DebugToDo(message: string)` before a node,
* Skip tests with `TestEnvironment.DebugSkip()` before a node,
* Only run specific tests with `TestEnvironment.DebugFocus()` before a node.

## Usage and example

Given a root Instance, `Tester` runs tests using descendant or root [ModuleScripts](https://create.roblox.com/docs/reference/engine/classes/ModuleScript) whose name ends with the suffix `.test`.

To test the following module:

**ReplicatedStorage**/**String**

```lua
local String = {}

function String.isEmpty(str: string): boolean
    return str == "" or str:match("[%s]+") == str
end

function String.startsWith(str: string, token: string): boolean
    return str:sub(1, #token) == token
end

return String
```

Create a new ModuleScript named `String.test`.
The test module must return a function, and takes in two arguments:

* TestEnvironment: a class shared by all test modules to create tests,
* TestContext: a dictionary shared by all test modules to store shared variables.

**ReplicatedStorage**/**String**/**String.test**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local String = require(ReplicatedStorage.String)
local Tester = require(ReplicatedStorage.Tester)

return function(environment: Tester.TestEnvironment, context: Tester.TestContext): ()
    local detail = environment.Detail
    local expect = environment.Expect
    local toEqual = environment.ToEqual
    
    -- Group the tests for String.isEmpty using a `detail` node.
    detail("is empty", function(): ()
        -- An `expect` node is always followed by a `to[...]` validation check.
        expect(String.isEmpty("    "))
        toEqual(true)
        
        expect(String.isEmpty("Hello world!"))
        toEqual(false)
    end)
    
    detail("starts with", function(): ()
        expect(String.startsWith("0b111111", "0x"))
        toEqual(false)
        
        expect(String.startsWith("0xFFFFFF", "0x"))
        toEqual(true)
    end)
end
```

Finally, run the tests using a Script or the command bar, with the Tester library installed under `ReplicatedStorage` in this example:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tester = require(ReplicatedStorage.Tester)
local tests = Tester.new(ReplicatedStorage.String)
tests:PrintResultsDefault()
```

The default output looks something like this:

```
=============== Test results ===============

Build Time: 0.173ms
Run Time: 0.004ms

4 Passed Test(s)
0 Failed Test(s)
0 Skipped Test(s)

Successfully built tests
Successfully ran tests

============================================
```

Any errors occurring while building or running tests are reported to the output with the path to the error and the error itself.

## Other examples

It is also possible to listen for `Tester` starting and ending testing, or when a new scope is entered or exited:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tester = require(ReplicatedStorage.Tester)

return function(environment: Tester.TestEnvironment, context: Tester.TestContext): ()
    environment.OnStart(function(): ()
        print("Tester started!")
    end)
    environment.OnEnd(function(): ()
        print("Tester ended!")
    end)
    
    -- Listen for scopes being entered and exited (either a test module or a detail node)
    local scopeLevel = 0
    environment.OnScopeEnter(function(): ()
        scopeLevel += 1
        print(`Scope entered, scope level: {scopeLevel}`)
    end)
    environment.OnScopeExit(function(): ()
        scopeLevel -= 1
        print(`Scope exited, scope level: {scopeLevel}`)
    end)

    ...
end
```

Here is another example to only run tests in "is empty" and skip the second test in "is empty":

**ReplicatedStorage**/**String**/**String.test**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local String = require(ReplicatedStorage.String)
local Tester = require(ReplicatedStorage.Tester)

return function(environment: Tester.TestEnvironment, context: Tester.TestContext): ()
    local detail = environment.Detail
    local expect = environment.Expect
    local toEqual = environment.ToEqual
    local debugFocus = environment.DebugFocus
    local debugSkip = environment.DebugSkip

    -- Tests which are descendants of "is empty" will run
    debugFocus()
    detail("is empty", function(): ()
        expect(String.isEmpty("    "))
        toEqual(true)
        
        -- This specific test will be skipped
        debugSkip() 
        expect(String.isEmpty("Hello world!"))
        toEqual(false)
    end)
    
    -- These tests will not run
    detail("starts with", function(): ()
        expect(String.startsWith("0b111111", "0x"))
        toEqual(false)
        
        expect(String.startsWith("0xFFFFFF", "0x"))
        toEqual(true)
    end)
end
```

Using debug nodes (`DebugToDo`, `DebugFocus` or `DebugSkip`) adds a message to the output to notify the user. Parent debug nodes always have priority over children debug nodes.

## Authors

* [@leandrelab](https://www.github.com/leandrelab)
