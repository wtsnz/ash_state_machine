# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.StaleDataTest do
  use ExUnit.Case

  # Each test passes a stale `open` copy of an order that has since been paid.
  setup do
    stale = RefetchedOrder.create!()
    RefetchedOrder.pay!(stale)
    %{stale: stale}
  end

  defp stored_state(order), do: Ash.get!(RefetchedOrder, order.id).state

  test "transition_state after a refetch checks the refetched record", %{stale: stale} do
    assert {:error, %Ash.Error.Invalid{errors: [%AshStateMachine.Errors.NoMatchingTransition{}]}} =
             RefetchedOrder.cancel_after_refetch(stale)

    assert stored_state(stale) == :paid
  end

  test "next_state after a refetch picks the next state of the refetched record",
       %{stale: stale} do
    assert RefetchedOrder.advance_after_refetch!(stale).state == :shipped
    assert stored_state(stale) == :shipped
  end

  test "a non-atomic transition doesn't overwrite a state it can't start from",
       %{stale: stale} do
    assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
             RefetchedOrder.cancel(stale)

    assert stored_state(stale) == :paid
  end

  test "a transition from `:*` applies whatever the stored state", %{stale: stale} do
    assert RefetchedOrder.archive!(stale).state == :archived
    assert stored_state(stale) == :archived
  end

  test "a fresh record still transitions" do
    order = RefetchedOrder.create!()

    assert RefetchedOrder.cancel_after_refetch!(order).state == :cancelled
    assert stored_state(order) == :cancelled
  end
end
