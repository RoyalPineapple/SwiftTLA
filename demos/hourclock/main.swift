var clock = HourClock.initial
print("Hour \(clock.hr):00")
for _ in 1...14 {
    clock.apply(.tick)
    print("Hour \(clock.hr):00")
}
