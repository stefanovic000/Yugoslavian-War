-- tests/run.lua
-- Minimal test runner executed by `lovec . --test` (test.bat).

local run = {}

local suites = {
  { name = "util", cases = require("tests.test_util") },
  { name = "class", cases = require("tests.test_class") },
  { name = "shared", cases = require("tests.test_shared") },
  { name = "match", cases = require("tests.test_match") },
}

function run.run()
  print("")
  print("======================================================")
  print(" YUGOSLAVIAN WAR test suite")
  print("======================================================")

  local passed, failed = 0, 0
  local failures = {}

  for _, suite in ipairs(suites) do
    print(string.format("[%s]", suite.name))
    for _, case in ipairs(suite.cases) do
      local ok, err = xpcall(case.fn, debug.traceback)
      if ok then
        passed = passed + 1
        print("  PASS  " .. case.name)
      else
        failed = failed + 1
        failures[#failures + 1] = { suite = suite.name, name = case.name, err = tostring(err) }
        print("  FAIL  " .. case.name)
      end
    end
  end

  print("------------------------------------------------------")
  if failed > 0 then
    for _, failure in ipairs(failures) do
      print(string.format("FAILED [%s] %s", failure.suite, failure.name))
      print(failure.err)
      print("")
    end
  end

  print(string.format(" %d passed, %d failed", passed, failed))
  print("======================================================")
  print("")

  return failed == 0
end

return run
