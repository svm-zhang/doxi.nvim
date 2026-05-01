local importer = require("doxi.importer")
local t = require("tests")

return {
  {
    name = "imports an indented contiguous doctest block",
    fn = function()
      local result, err = importer.parse_doctest_block({
        "    >>> def f(x):",
        "    ...     return x + 1",
        "    >>> f(3)",
        "    4",
        "    >>> 1 / 0",
        "    Traceback (most recent call last):",
        "    ...",
        "    ZeroDivisionError: division by zero",
      })

      t.assert_equal(err, nil, "The importer should accept a valid doctest block.")
      t.assert_equal(result.indent, "    ", "The importer should preserve the surrounding docstring indent.")
      t.assert_deep_equal(result.source_lines, {
        "def f(x):",
        "    return x + 1",
        "f(3)",
        "1 / 0",
      })
    end,
  },
  {
    name = "accepts multiple doctest groups separated only by blank lines",
    fn = function()
      local result, err = importer.parse_doctest_block({
        "    >>> x = 1",
        "    >>> x + 1",
        "    2",
        "    ",
        "    >>> y = 2",
        "    >>> y + 1",
        "    3",
      })

      t.assert_equal(err, nil, "Blank lines between doctest groups should be accepted.")
      t.assert_deep_equal(result.source_lines, {
        "x = 1",
        "x + 1",
        "y = 2",
        "y + 1",
      })
    end,
  },
  {
    name = "rejects prose inside a selected doctest region",
    fn = function()
      local result, err = importer.parse_doctest_block({
        "    >>> x = 1",
        "    >>> x + 1",
        "    2",
        "    ",
        "    Some doctest title:",
        "    >>> y = 2",
        "    >>> y + 1",
        "    3",
      })

      t.assert_equal(result, nil, "Prose inside the selected doctest region should be rejected.")
      t.assert_equal(err, "Invalid doctest block: unexpected prose or title at line 5.")
    end,
  },
  {
    name = "rejects selections without prompts",
    fn = function()
      local result, err = importer.parse_doctest_block({
        "plain text",
        "still plain text",
      })

      t.assert_equal(result, nil, "The importer should reject selections without doctest prompts.")
      t.assert_equal(err, "Selection does not start with a doctest prompt.")
    end,
  },
}
