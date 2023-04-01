; TIMER - programmable lab timer + clock
; Written for 8048 Assembler/Simulator/Programmer by AceBus

; R5 - timer reg (timer decrements it)
; timer isr use register bank 1, main code use register bank 0

hd44780_loop_delay EQU 20
timer_reload_value EQU 0100h-50
timer_per_second   EQU 250 ; real value
;timer_per_second   EQU 5 ; debug value
timer_signal_time  EQU 3

DATAORG 31 ;skip registers location for DS
;**************************************************************************
        ORG     0 ;reset interrupt location
        JMP     reset

        ORG     3 ;input interrupt location
        RETR

        ORG     7 ;timer interrupt location
        JMP timer_isr
;**************************************************************************
btn_state DS 1 ; bit0 - MODE, bit1 - PLUS 
setup_state DS 1 ;0-5 - number of value to set, other - normal work
invert_selected_item DS 1 ;counter 
reset:
        ;clear memory and regs
        MOV R0, #127
        MOV A, #0
init_clean_ram:
        MOV @R0, A
        DJNZ R0, init_clean_ram
        
        ;other init
        CALL init
        
        CPL F1
        CLR F0
        CPL F0
        
display_update_loop:        

        MOV A, #086h ; [Set DDRAM address] first line
        CALL send_to_display       
        
        MOV R1, #setup_state
        MOV A, @R1
        MOV R2, A
        
        MOV R0, #time_now_h
        CALL print_time
        
        MOV A, #0C7h ; [Set DDRAM address] second line
        CALL send_to_display   
                
        MOV A, R2
        ADD A, #0FDh
        MOV R2, A
        
        MOV R0, #time_alarm_h
        CALL print_time
        
        ;wait a bit
        MOV A, #2
        CALL delay_timer

        MOV R1, #invert_selected_item
        INC @R1
        MOV A, @R1
        ADD A, #096h
        JZ do_invert
        MOV A, @R1
        ADD A, #07Dh
        JZ do_clear_invert
        JMP do_not_invert
do_clear_invert:
        MOV @R1, #0
do_invert:
        CPL F1
do_not_invert:

        MOV R0, #setup_state
        MOV R1, #btn_state
        
        ;test MODE button
        MOV A, @R1
        JNT0 mode_btn_free
        ;process MODE high
        ANL A, #001h
        JNZ mode_check_end
        MOV A, @R1
        ;у хомяков 16 зубов, 4 из них - передние резцы
        ORL A, #001h
        MOV @R1, A
        
        ;increment setup state, use 0 if 7
        INC @R0
        MOV A, @R0
        ADD A, #0F9h 
        JNZ do_not_reload_setup_state
        MOV @R0, #0
do_not_reload_setup_state:
        MOV A, @R0
        
        MOV R1, #start_time_count
        ADD A, #0FAh
        JNZ disable_time
        MOV @R1, #1
        JMP time_processed
disable_time:
        MOV @R1, #0
time_processed:
        
        JMP mode_check_end
mode_btn_free:
        ;process MODE low
        ANL A, #0FEh
        MOV @R1, A
mode_check_end:

        MOV R1, #btn_state
        ;test PLUS button
        MOV A, @R1
        JNT1 plus_btn_free
        ;process PLUS high
        ANL A, #002h
        JNZ plus_check_end
        MOV A, @R1
        ORL A, #002h
        MOV @R1, A
        
        MOV A, @R0
        CLR C
        ADD A, #0FAh
        JC plus_check_end
        
        ;load time addr
        MOV A, @R0
        ADD A, #time_now_h
        MOV R1, A
        
        MOV A, @R0
        JZ it_is_hour
        ADD A, #0FDh
        JZ it_is_hour
        MOV R4, #060h
        JMP increase
it_is_hour:
        MOV R4, #024h
increase:
        MOV A, @R1
        CALL inc_bcd_with_maximum
        MOV @R1, A
        
        JMP plus_check_end
        
plus_btn_free:
        ;process PLUS low
        ANL A, #0FDh
        MOV @R1, A
plus_check_end:

        JMP display_update_loop
;**************************************************************************
; R0 - pointer to h-m-s bcd bytes
; R2 - number of blinking led
print_time:

        CLR C
        CLR F0

        ;hour
        MOV A, R2
        JNZ print_time_show_hour
        JF1 print_time_show_hour

        MOV A, #' '
        CALL send_to_display
        CALL send_to_display
        JMP print_time_skip_show_hour
print_time_show_hour:
        MOV A, @R0
        CALL display_send_hex
print_time_skip_show_hour:

        ;colon
        MOV A, #':'
        CALL send_to_display

        INC R0
                
        ;minute
        MOV A, R2
        ADD A, #0FFh
        JNZ print_time_show_minute
        JF1 print_time_show_minute

        MOV A, #' '
        CALL send_to_display
        CALL send_to_display
        JMP print_time_skip_show_minute
print_time_show_minute:
        MOV A, @R0
        CALL display_send_hex
print_time_skip_show_minute:

        ;colon
        MOV A, #':'
        CALL send_to_display
                
        INC R0
        
        ;second
        MOV A, R2
        ADD A, #0FEh
        JNZ print_time_show_second
        JF1 print_time_show_second

        MOV A, #' '
        CALL send_to_display
        CALL send_to_display
        JMP print_time_skip_show_second
print_time_show_second:
        MOV A, @R0
        CALL display_send_hex
print_time_skip_show_second:

        RETR
;**************************************************************************
; A - data to send
; F0 - register select, 0 - data, 1 - command
send_to_display:
        MOV R7, A
        SWAP A
        ANL A, #00Fh

        JF0 send_to_display_send1
        ORL A, #010h ;it it data
send_to_display_send1:

        OUTL P1, A
        ORL P1, #020h
        
        MOV A, #hd44780_loop_delay
        CALL delay_loop
        
        ANL P1, #0DFh

        MOV A, #hd44780_loop_delay
        CALL delay_loop
        
        MOV A, R7
        ANL A, #00Fh

        JF0 send_to_display_send2
        ORL A, #010h ;it it data
send_to_display_send2:

        OUTL P1, A
        ORL P1, #020h
        
        MOV A, #hd44780_loop_delay
        CALL delay_loop
        
        ANL P1, #0DFh
        
        MOV A, #hd44780_loop_delay
        CALL delay_loop
        MOV A, R7
        RETR
;**************************************************************************
;A - number of 4ms intervals to wait
delay_timer:
        MOV R5, A
delay_timer_wait:
        MOV A, R5
        JNZ delay_timer_wait
        RETR
;**************************************************************************
;A - number of loops
delay_loop:
        XCH A, R0
delay_loop_loop:
        DJNZ R0, delay_loop_loop
        XCH A, R0
        RETR
;**************************************************************************
display_send_hex:        
        MOV R6, A
        SWAP A
        ANL A, #00Fh
        
        MOV R4, A
        ADD A, #0F6h
        MOV A, R4
        JNC display_send_hex_is_not_hex1
        ADD A, #'A'-('0'+10)
display_send_hex_is_not_hex1:
        ADD A, #'0'
        
        CALL send_to_display
        
        MOV A, R6
        ANL A, #00Fh
        
        MOV R4, A
        ADD A, #0F6h
        MOV A, R4
        JNC display_send_hex_is_not_hex2
        ADD A, #'A'-('0'+10)
display_send_hex_is_not_hex2:
        ADD A, #'0'
        
        CALL send_to_display

        RETR
;**************************************************************************
;A - pointer to current page program data null-terminated str
hello_msg1:  DB   '   LAB  TIMER',0
hello_msg2:  DB   '   KP1816BE39',0
work_msg1: DB 'TIME:',0
work_msg2: DB 'ALARM:',0
send_display_str:
        CLR F0
        MOV R6, A
        MOVP A, @A
        JZ send_display_str_end
        call send_to_display
        MOV A, R6
        INC A
        JMP send_display_str
send_display_str_end:
        RETR
;**************************************************************************
time_now_h ds 1
time_now_m ds 1
time_now_s ds 1
time_alarm_h ds 1
time_alarm_m ds 1
time_alarm_s ds 1
start_time_count ds 1
backup_a ds 1
timer_isr: ;250Hz, every 4 ms
        SEL RB1
        MOV R0, #backup_a
        MOV @R0, A
        
        DJNZ R3, timer_isr_time_update_skip
        MOV R3, #timer_per_second
        ;update time
              
        MOV R0, #start_time_count
        MOV A, @R0
        JZ timer_isr_time_update_skip
        
        MOV R1, #time_now_s
        MOV A, @R1
        MOV R4, #060h
        CALL inc_bcd_with_maximum
        MOV @R1, A
        
        JNC timer_isr_time_update_check_alarm
        
        DEC R1
        MOV A, @R1
        MOV R4, #060h
        CALL inc_bcd_with_maximum
        MOV @R1, A
        
        JNC timer_isr_time_update_check_alarm
        
        DEC R1
        MOV A, @R1
        MOV R4, #024h
        CALL inc_bcd_with_maximum
        MOV @R1, A
        
timer_isr_time_update_check_alarm:
        
        MOV R1, #time_now_h
        MOV R0, #time_alarm_h
        MOV A, @R0
        CPL A
        INC A
        ADD A, @R1
        JNZ timer_isr_time_update_end
        
        MOV R1, #time_now_m
        MOV R0, #time_alarm_m
        MOV A, @R0
        CPL A
        INC A
        ADD A, @R1
        JNZ timer_isr_time_update_end
        
        MOV R1, #time_now_s
        MOV R0, #time_alarm_s
        MOV A, @R0
        CPL A
        INC A
        ADD A, @R1
        JNZ timer_isr_time_update_end
        
        ;alarm!
        MOV R2, #timer_signal_time+1
        ANL P2, #0EFh ;enable relay

timer_isr_time_update_end:
        MOV A, R2
        JZ timer_isr_alarm_not_in_process
        DEC A
        MOV R2, A
        JNZ timer_isr_time_update_skip
timer_isr_alarm_not_in_process:
        ORL P2, #010h ;disable relay
        
timer_isr_time_update_skip:
        
        ;re-init timer
        MOV A, #timer_reload_value;set timer start value
        MOV T, A
        
        MOV R0, #backup_a
        MOV A, @R0
        SEL RB0
        
        ;decrement timer register
        XCH A, R5
        JZ timer_isr_end
        DEC A
timer_isr_end:
        XCH A, R5
        
        RETR
;**************************************************************************
init:
        MOV A, #timer_reload_value;set timer start value
        MOV T, A
        STRT T ;start timer
        EN TCNTI ;enable timer interrupt

        ;setup 44780 to 4-bit mode
        MOV A, #002h
        OUTL P1, A
        
        MOV A, #hd44780_loop_delay
        CALL delay_loop
        
        ORL P1, #020h
        
        MOV A, #hd44780_loop_delay
        CALL delay_loop

        ANL P1, #0DFh
        
        MOV A, #hd44780_loop_delay
        CALL delay_loop
        
        ;F0=1, so commands to be sended
        CLR F0
        CPL F0

        MOV A, #001h ; [Clear display]
        CALL send_to_display      

        MOV A, #2
        CALL delay_timer        

        MOV A, #028h ; [Function set] 4-bit + 2 lines + 5x8 dot character font
        CALL send_to_display
        
        MOV A, #006h ; [Entry mode set] increment+no shift
        CALL send_to_display
        
        MOV A, #00Ch ; [Display on/off control] on+no cursor+no shift
        CALL send_to_display
        
        MOV A, #hello_msg1
        CALL send_display_str
        
        MOV A, #0C0h ; [Set DDRAM address] second line
        CALL send_to_display    
        
        MOV A, #hello_msg2
        CALL send_display_str

        MOV A, #250 ;1 second delay
        CALL delay_timer   

        MOV A, #001h ; [Clear display]
        CALL send_to_display      

        MOV A, #2
        CALL delay_timer   
        
        MOV A, #work_msg1
        CALL send_display_str
        
        MOV A, #0C0h ; [Set DDRAM address] second line
        CALL send_to_display    
        
        MOV A, #work_msg2
        CALL send_display_str
        RETR
;**************************************************************************
; A - inout value to increase
; R4 - maximum value (not including)
; C - carry happens
inc_bcd_with_maximum:

        ADD A, #1
        DA A
        XCH A, R4
        CPL A
        ADD A, R4
        INC A
        CLR C
        JNZ not_maximum
        CPL C
        MOV R4, #0
not_maximum:
        XCH A, R4
        
        RET

;**************************************************************************
        END
