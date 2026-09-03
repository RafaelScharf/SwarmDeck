import Darwin
var m: Int32 = 0
var s: Int32 = 0
openpty(&m, &s, nil, nil, nil)
