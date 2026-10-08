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

  test "next_state after a refetch checks its target against the refetched record",
       %{stale: stale} do
    assert {:error, %Ash.Error.Invalid{errors: [%AshStateMachine.Errors.NoMatchingTransition{}]}} =
             RefetchedOrder.advance_after_refetch(stale)

    assert stored_state(stale) == :paid
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

  # `next_state/0` mustn't choose a different target from the refetched record
  # after changes, validations and policies have used the one it chose first.
  describe "next_state with a stale copy and a refetch" do
    setup do
      stale = Ash.create!(GuardedOrder, %{}, authorize?: false)
      Ash.update!(stale, %{}, action: :pay, authorize?: false)
      %{stale: stale}
    end

    defp guarded_state(order), do: Ash.get!(GuardedOrder, order.id, authorize?: false).state

    test "keeps later changes consistent with the target", %{stale: stale} do
      assert {:error, _} = Ash.update(stale, %{}, action: :advance_with_note, authorize?: false)
      assert guarded_state(stale) == :paid
    end

    test "honours validations of the target", %{stale: stale} do
      assert {:error, _} = Ash.update(stale, %{}, action: :advance_validated, authorize?: false)
      assert guarded_state(stale) == :paid
    end

    test "honours policies on the target", %{stale: stale} do
      assert {:error, _} = Ash.update(stale, %{}, action: :advance_authorized, authorize?: true)
      assert guarded_state(stale) == :paid
    end
  end
end
