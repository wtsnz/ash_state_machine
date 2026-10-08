# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.BuiltinChanges.TransitionState do
  @moduledoc false
  use Ash.Resource.Change

  def change(changeset, opts, _) do
    if recheck_after_hooks?(changeset) do
      changeset
      |> AshStateMachine.transition_state(opts[:target], require_stored_state?: false)
      |> Ash.Changeset.before_action(&AshStateMachine.transition_state(&1, opts[:target]))
    else
      AshStateMachine.transition_state(changeset, opts[:target])
    end
  end

  # Changes such as `get_and_lock_for_update/0` refetch `changeset.data` in a
  # `before_action` hook, after `change/3` has checked the caller's copy. When an
  # earlier change has added such a hook, check the transition again once it has
  # run. A hook is only added in that case, so that an action with
  # `atomic_upgrade? true` can still be upgraded.
  @doc false
  def recheck_after_hooks?(%{action_type: :update, before_action: [_ | _]}), do: true
  def recheck_after_hooks?(_changeset), do: false

  def atomic(changeset, opts, _) do
    transitions =
      AshStateMachine.Info.state_machine_transitions(changeset.resource, changeset.action.name)

    attribute = AshStateMachine.Info.state_machine_state_attribute!(changeset.resource)

    old_state = expr(^ref(attribute))
    target = maybe_cast_to_atom(opts[:target])
    all_states = AshStateMachine.Info.state_machine_all_states(changeset.resource)

    if !Ash.Expr.expr?(target) && target not in all_states do
      AshStateMachine.no_such_state(changeset, target)

      {:atomic,
       %{
         attribute =>
           expr(
             error(
               AshStateMachine.Errors.NoMatchingTransition,
               %{
                 old_state: ^old_state,
                 target: ^target,
                 action: ^changeset.action.name
               }
             )
           )
       }}
    else
      states_expr =
        Enum.reduce(transitions, false, fn transition, expr ->
          state_expr =
            expr(
              ^old_state in ^List.wrap(transition.from) and ^target in ^List.wrap(transition.to)
            )

          if expr == false do
            state_expr
          else
            expr(^state_expr or ^expr)
          end
        end)

      has_matching_transition =
        {:atomic, [], expr(not (^states_expr)),
         expr(
           error(
             AshStateMachine.Errors.NoMatchingTransition,
             %{
               old_state: ^old_state,
               target: ^target,
               action: ^changeset.action.name
             }
           )
         )}

      {:atomic, %{attribute => opts[:target]},
       [
         has_matching_transition
       ]}
    end
  end

  def maybe_cast_to_atom(target) when is_binary(target) do
    String.to_existing_atom(target)
  rescue
    _ -> target
  end

  def maybe_cast_to_atom(target), do: target
end
