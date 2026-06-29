    lu12i.w $r5, 0x1fb00      # r5 = 0x1fb00000
    ld.w    $r6, $r5, 0x10    # r6 = counter start
    addi.w  $r7, $r0, 0       # sum = 0
    addi.w  $r8, $r0, 1       # i = 1
    addi.w  $r9, $r0, 11      # limit = 11
loop:
    add.w   $r7, $r7, $r8     # sum += i
    addi.w  $r8, $r8, 1       # i++
    bne     $r8, $r9, loop    # while i != 11   => sum = 55 (0x37)
    st.w    $r7, $r5, 0x0     # seg7 <- sum (0x37)
    ld.w    $r10, $r5, 0x10   # counter end
    sub.w   $r11, $r10, $r6   # cycles = end - start
    st.w    $r11, $r5, 0x0    # seg7 <- cycle count
done:
    b       done             # halt
