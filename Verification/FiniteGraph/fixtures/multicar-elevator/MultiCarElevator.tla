---- MODULE MultiCarElevator ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES cars, calls, lastMoveDoorClosed

vars == <<cars, calls, lastMoveDoorClosed>>

TypeOK == (((((cars["carA"]).floor \in {0, 1, 2}) /\ ((cars["carB"]).floor \in {0, 1, 2})) /\ ((cars["carA"]).rider \in {"none", "alice", "bob"})) /\ ((cars["carB"]).rider \in {"none", "alice", "bob"}))
FloorBounds == (((((cars["carA"]).floor >= 0) /\ ((cars["carA"]).floor <= 2)) /\ ((cars["carB"]).floor >= 0)) /\ ((cars["carB"]).floor <= 2))
ClosedDoorMovement == (lastMoveDoorClosed = TRUE)
NoDoubleAssignment == ((((cars["carA"]).rider = "none") \/ ((cars["carB"]).rider = "none")) \/ ((cars["carA"]).rider /= (cars["carB"]).rider))

StateConstraint == (Cardinality(calls) <= 1)

Init ==
  /\ cars = [__tla_fn_0 \in {"carA", "carB"} |-> CASE (__tla_fn_0 = "carA") -> [doorsOpen |-> FALSE, floor |-> 0, rider |-> "none"] [] (__tla_fn_0 = "carB") -> [doorsOpen |-> FALSE, floor |-> 2, rider |-> "none"]]
  /\ calls = {}
  /\ lastMoveDoorClosed = TRUE

request(person, floor, direction) == ((((~([direction |-> direction, floor |-> floor, person |-> person] \in calls)) /\ calls' = (calls \cup {[direction |-> direction, floor |-> floor, person |-> person]})) /\ UNCHANGED cars) /\ UNCHANGED lastMoveDoorClosed)
request__0_0_0 == request("alice", 0, "up")
request__0_0_1 == request("alice", 0, "down")
request__0_1_0 == request("alice", 1, "up")
request__0_1_1 == request("alice", 1, "down")
request__0_2_0 == request("alice", 2, "up")
request__0_2_1 == request("alice", 2, "down")
request__1_0_0 == request("bob", 0, "up")
request__1_0_1 == request("bob", 0, "down")
request__1_1_0 == request("bob", 1, "up")
request__1_1_1 == request("bob", 1, "down")
request__1_2_0 == request("bob", 2, "up")
request__1_2_1 == request("bob", 2, "down")
assign(person, car, direction) == ((((((Cardinality(calls) = 1) /\ (((cars["carA"]).rider /= person) /\ ((cars["carB"]).rider /= person))) /\ ((cars[car]).rider = "none")) /\ cars' = [cars EXCEPT ![car] = [cars[car] EXCEPT !["rider"] = person]]) /\ UNCHANGED calls) /\ UNCHANGED lastMoveDoorClosed)
assign__0_0_0 == assign("alice", "carA", "up")
assign__0_0_1 == assign("alice", "carA", "down")
assign__0_1_0 == assign("alice", "carB", "up")
assign__0_1_1 == assign("alice", "carB", "down")
assign__1_0_0 == assign("bob", "carA", "up")
assign__1_0_1 == assign("bob", "carA", "down")
assign__1_1_0 == assign("bob", "carB", "up")
assign__1_1_1 == assign("bob", "carB", "down")
move(car, direction, floor) == ((((((cars[car]).doorsOpen = FALSE) /\ ((cars[car]).floor /= floor)) /\ cars' = [cars EXCEPT ![car] = [cars[car] EXCEPT !["floor"] = floor]]) /\ lastMoveDoorClosed' = TRUE) /\ UNCHANGED calls)
move__0_0_0 == move("carA", "up", 0)
move__0_0_1 == move("carA", "up", 1)
move__0_0_2 == move("carA", "up", 2)
move__0_1_0 == move("carA", "down", 0)
move__0_1_1 == move("carA", "down", 1)
move__0_1_2 == move("carA", "down", 2)
move__1_0_0 == move("carB", "up", 0)
move__1_0_1 == move("carB", "up", 1)
move__1_0_2 == move("carB", "up", 2)
move__1_1_0 == move("carB", "down", 0)
move__1_1_1 == move("carB", "down", 1)
move__1_1_2 == move("carB", "down", 2)
openDoor(car, floor, direction) == (((((cars[car]).doorsOpen = FALSE) /\ cars' = [cars EXCEPT ![car] = [cars[car] EXCEPT !["doorsOpen"] = TRUE]]) /\ UNCHANGED calls) /\ UNCHANGED lastMoveDoorClosed)
openDoor__0_0_0 == openDoor("carA", 0, "up")
openDoor__0_0_1 == openDoor("carA", 0, "down")
openDoor__0_1_0 == openDoor("carA", 1, "up")
openDoor__0_1_1 == openDoor("carA", 1, "down")
openDoor__0_2_0 == openDoor("carA", 2, "up")
openDoor__0_2_1 == openDoor("carA", 2, "down")
openDoor__1_0_0 == openDoor("carB", 0, "up")
openDoor__1_0_1 == openDoor("carB", 0, "down")
openDoor__1_1_0 == openDoor("carB", 1, "up")
openDoor__1_1_1 == openDoor("carB", 1, "down")
openDoor__1_2_0 == openDoor("carB", 2, "up")
openDoor__1_2_1 == openDoor("carB", 2, "down")
board(person, car, floor) == ((((((cars[car]).doorsOpen = TRUE) /\ ((cars[car]).rider = person)) /\ calls' = (calls \ {[direction |-> "up", floor |-> floor, person |-> person]})) /\ UNCHANGED cars) /\ UNCHANGED lastMoveDoorClosed)
board__0_0_0 == board("alice", "carA", 0)
board__0_0_1 == board("alice", "carA", 1)
board__0_0_2 == board("alice", "carA", 2)
board__0_1_0 == board("alice", "carB", 0)
board__0_1_1 == board("alice", "carB", 1)
board__0_1_2 == board("alice", "carB", 2)
board__1_0_0 == board("bob", "carA", 0)
board__1_0_1 == board("bob", "carA", 1)
board__1_0_2 == board("bob", "carA", 2)
board__1_1_0 == board("bob", "carB", 0)
board__1_1_1 == board("bob", "carB", 1)
board__1_1_2 == board("bob", "carB", 2)
closeDoor(car, floor, direction) == (((((cars[car]).doorsOpen = TRUE) /\ cars' = [cars EXCEPT ![car] = [cars[car] EXCEPT !["doorsOpen"] = FALSE]]) /\ UNCHANGED calls) /\ UNCHANGED lastMoveDoorClosed)
closeDoor__0_0_0 == closeDoor("carA", 0, "up")
closeDoor__0_0_1 == closeDoor("carA", 0, "down")
closeDoor__0_1_0 == closeDoor("carA", 1, "up")
closeDoor__0_1_1 == closeDoor("carA", 1, "down")
closeDoor__0_2_0 == closeDoor("carA", 2, "up")
closeDoor__0_2_1 == closeDoor("carA", 2, "down")
closeDoor__1_0_0 == closeDoor("carB", 0, "up")
closeDoor__1_0_1 == closeDoor("carB", 0, "down")
closeDoor__1_1_0 == closeDoor("carB", 1, "up")
closeDoor__1_1_1 == closeDoor("carB", 1, "down")
closeDoor__1_2_0 == closeDoor("carB", 2, "up")
closeDoor__1_2_1 == closeDoor("carB", 2, "down")
completeRide(person, car, floor) == (((((((cars[car]).doorsOpen = TRUE) /\ ((cars[car]).rider = person)) /\ ((cars[car]).floor = floor)) /\ cars' = [cars EXCEPT ![car] = [cars[car] EXCEPT !["rider"] = "none"]]) /\ UNCHANGED calls) /\ UNCHANGED lastMoveDoorClosed)
completeRide__0_0_0 == completeRide("alice", "carA", 0)
completeRide__0_0_1 == completeRide("alice", "carA", 1)
completeRide__0_0_2 == completeRide("alice", "carA", 2)
completeRide__0_1_0 == completeRide("alice", "carB", 0)
completeRide__0_1_1 == completeRide("alice", "carB", 1)
completeRide__0_1_2 == completeRide("alice", "carB", 2)
completeRide__1_0_0 == completeRide("bob", "carA", 0)
completeRide__1_0_1 == completeRide("bob", "carA", 1)
completeRide__1_0_2 == completeRide("bob", "carA", 2)
completeRide__1_1_0 == completeRide("bob", "carB", 0)
completeRide__1_1_1 == completeRide("bob", "carB", 1)
completeRide__1_1_2 == completeRide("bob", "carB", 2)

Next ==
  \/ request__0_0_0
  \/ request__0_0_1
  \/ request__0_1_0
  \/ request__0_1_1
  \/ request__0_2_0
  \/ request__0_2_1
  \/ request__1_0_0
  \/ request__1_0_1
  \/ request__1_1_0
  \/ request__1_1_1
  \/ request__1_2_0
  \/ request__1_2_1
  \/ assign__0_0_0
  \/ assign__0_0_1
  \/ assign__0_1_0
  \/ assign__0_1_1
  \/ assign__1_0_0
  \/ assign__1_0_1
  \/ assign__1_1_0
  \/ assign__1_1_1
  \/ move__0_0_0
  \/ move__0_0_1
  \/ move__0_0_2
  \/ move__0_1_0
  \/ move__0_1_1
  \/ move__0_1_2
  \/ move__1_0_0
  \/ move__1_0_1
  \/ move__1_0_2
  \/ move__1_1_0
  \/ move__1_1_1
  \/ move__1_1_2
  \/ openDoor__0_0_0
  \/ openDoor__0_0_1
  \/ openDoor__0_1_0
  \/ openDoor__0_1_1
  \/ openDoor__0_2_0
  \/ openDoor__0_2_1
  \/ openDoor__1_0_0
  \/ openDoor__1_0_1
  \/ openDoor__1_1_0
  \/ openDoor__1_1_1
  \/ openDoor__1_2_0
  \/ openDoor__1_2_1
  \/ board__0_0_0
  \/ board__0_0_1
  \/ board__0_0_2
  \/ board__0_1_0
  \/ board__0_1_1
  \/ board__0_1_2
  \/ board__1_0_0
  \/ board__1_0_1
  \/ board__1_0_2
  \/ board__1_1_0
  \/ board__1_1_1
  \/ board__1_1_2
  \/ closeDoor__0_0_0
  \/ closeDoor__0_0_1
  \/ closeDoor__0_1_0
  \/ closeDoor__0_1_1
  \/ closeDoor__0_2_0
  \/ closeDoor__0_2_1
  \/ closeDoor__1_0_0
  \/ closeDoor__1_0_1
  \/ closeDoor__1_1_0
  \/ closeDoor__1_1_1
  \/ closeDoor__1_2_0
  \/ closeDoor__1_2_1
  \/ completeRide__0_0_0
  \/ completeRide__0_0_1
  \/ completeRide__0_0_2
  \/ completeRide__0_1_0
  \/ completeRide__0_1_1
  \/ completeRide__0_1_2
  \/ completeRide__1_0_0
  \/ completeRide__1_0_1
  \/ completeRide__1_0_2
  \/ completeRide__1_1_0
  \/ completeRide__1_1_1
  \/ completeRide__1_1_2

Spec ==
  /\ Init
  /\ [][Next]_<<cars, calls, lastMoveDoorClosed>>

====

