local backend = require("doxi.backend")
local t = require("tests")

return {
  {
    name = "buffers chunked stdout until a full JSON response is available",
    fn = function()
      local instance = backend.new({
        interpreter_path = "python3",
      })
      local result
      local err

      instance.job_id = 1
      instance.pending[1] = function(response, response_err)
        result = response
        err = response_err
      end

      instance:_on_stdout(1, {
        '{"id":1,',
      })

      t.assert_equal(result, nil, "Partial stdout should not resolve the pending callback.")
      t.assert_true(instance.pending[1] ~= nil, "The request should remain pending until JSON is complete.")

      instance:_on_stdout(1, {
        '"ok":true,"result":{"chunks":[]}}',
        "",
      })

      t.wait_until(function()
        return result ~= nil or err ~= nil
      end, 1000, "Buffered stdout callback did not complete.")

      t.assert_equal(err, nil, "Chunked stdout should decode into a successful response.")
      t.assert_deep_equal(result, {
        chunks = {},
      })
      t.assert_equal(instance.pending[1], nil, "The pending callback should be cleared after dispatch.")
    end,
  },
}
