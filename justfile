check:
    mix format
    mix credo --mute-exit-status
    mix dialyzer
