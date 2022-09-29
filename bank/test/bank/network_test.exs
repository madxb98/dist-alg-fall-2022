defmodule Bank.NetworkTest do
  alias Bank.Network

  use ExUnit.Case
  doctest Network

  test "can send messages" do
    start_supervised!({Network, %{}})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, :sent} == Network.send_message({:atm, 1}, {:branch, 1}, :boo)
        Process.sleep(250)
      end)

    assert log =~ "Dear Student, you have sent a message"
  end
end
