ExUnit.configure(trace: false)
ExUnit.start()

Code.load_file("test/tesla/adapter/test_case.ex")
Code.load_file("test/tesla/middleware/test_case.exs")
