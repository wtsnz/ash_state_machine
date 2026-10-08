# SPDX-FileCopyrightText: 2023 ash_state_machine contributors <https://github.com/ash-project/ash_state_machine/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Refetch do
  @moduledoc false
  # Stands in for `get_and_lock_for_update/0`, which ETS can't run: refetches the
  # record in a `before_action` hook, the same way.
  use Ash.Resource.Change

  def change(changeset, _, _) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      %{changeset | data: Ash.get!(changeset.resource, changeset.data.id, authorize?: false)}
    end)
  end
end

defmodule RefetchedOrder do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:open]
    default_initial_state :open

    transitions do
      transition(:pay, from: :open, to: :paid)
      transition(:cancel, from: :open, to: :cancelled)
      transition(:cancel_after_refetch, from: :open, to: :cancelled)
      transition(:advance_after_refetch, from: :open, to: :paid)
      transition(:advance_after_refetch, from: :paid, to: :shipped)
      transition(:archive, from: :*, to: :archived)
    end
  end

  actions do
    defaults [:read, :create]

    update :pay do
      change transition_state(:paid)
    end

    update :cancel do
      require_atomic? false
      change transition_state(:cancelled)
    end

    update :cancel_after_refetch do
      require_atomic? false
      change Refetch
      change transition_state(:cancelled)
    end

    update :advance_after_refetch do
      require_atomic? false
      change Refetch
      change next_state()
    end

    update :archive do
      require_atomic? false
      change transition_state(:archived)
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
  end

  code_interface do
    define :create
    define :pay
    define :cancel
    define :cancel_after_refetch
    define :advance_after_refetch
    define :archive
  end
end
