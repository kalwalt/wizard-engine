(module
  (import "wizeng" "rdtsc" (func $rdtsc (result i64)))
  (func $nop)
  (func $main (export "main") (result i32)
    (local $before i64)
    (local.set $before (call $rdtsc))
    (call $nop)
    (call $nop)
    (call $nop)
    (call $nop)
    (call $nop)
    (call $nop)
    (call $nop)
    (call $nop)
    (call $nop)
    (i64.sub (call $rdtsc) (local.get $before))
    i64.eqz
  )
)
