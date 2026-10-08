# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.NextState do
  @moduledoc false
  use Ash.Resource.Change

  # The target is chosen from the record passed to the action, and then checked
  # like `transition_state/1`'s, including again after an earlier lock. It isn't
  # chosen again from the locked record: policies, validations and later changes
  # have already seen this target.
  def change(changeset, _opts, context) do
    changeset.data
    |> AshStateMachine.possible_next_states(changeset.action.name)
    |> case do
      [to] ->
        AshStateMachine.BuiltinChanges.TransitionState.change(changeset, [target: to], context)

      [] ->
        Ash.Changeset.add_error(changeset, "Cannot determine next state: no next state available")

      _ ->
        Ash.Changeset.add_error(
          changeset,
          "Cannot determine next state: multiple next states available"
        )
    end
  end
end
