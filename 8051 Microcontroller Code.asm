; ===================================================================
; MENU + SERVO + COUNTER + INTERRUPTS
; Architecture: Flag-Based Super Loop + Breakable Delays
; Display: Dynamic "Mode X" status + Two-Step Confirm/Start Sequence
; Auto-Reset: Instantly returns to Menu after 10 cycles
; SW1 (P3.2) = STOP INSTANTLY | SW4 (P3.3) = RESET TO MENU INSTANTLY
; ===================================================================

; --- Hardware Definitions ---
LCD_DAT     EQU P0
LCD_EN      EQU P3.0
LCD_RW      EQU P3.1
LCD_RS      EQU P3.4

KEY_PORT    EQU P1
SERVO_PIN   EQU P3.5
SEG_PORT    EQU P2
DIS0        EQU P3.6
DIS1        EQU P3.7

; --- System RAM Variables ---
CYCLE_COUNT EQU 31H         
SPEED_MODE  EQU 32H         
TEMP_SPEED  EQU 33H         
UI_STATE    EQU 35H         ; 0=Menu, 1=Confirm, 2=Start, 3=Running, 4=Stop, 5=Complete
MOTOR_EN    EQU 36H         ; 0=Off, 1=Running
UI_DIRTY    EQU 37H         ; 1=Needs screen redraw, 0=Screen is up to date


; =========================================================
; CRASH-PROOF HARDWARE INTERRUPTS (Flags Only!)
; =========================================================
    ORG 0000H
    LJMP MAIN

    ; --- SW1 (STOP) - INT0 ---
    ORG 0003H
    MOV MOTOR_EN, #0        ; 1. Tell main loop to abort motor delays INSTANTLY
    MOV UI_STATE, #4        ; 2. Request "Emergency Stop" screen (State 4)
    MOV UI_DIRTY, #1        ; 3. Trigger LCD redraw
    RETI                    ; 4. Clean exit

    ; --- SW4 (RESET) - INT1 ---
    ORG 0013H
    MOV UI_STATE, #0        ; 1. Request "Main Menu" screen
    MOV UI_DIRTY, #1        ; 2. Trigger LCD redraw (breaks motor delays instantly)
    ; (MOTOR_EN is NOT changed here. Servo keeps running!)
    RETI                    ; 3. Clean exit


; =========================================================
; MAIN INITIALIZATION
; =========================================================
    ORG 0030H
MAIN:
    ; Hardware Setup
    SETB IT0                ; Trigger INT0 on falling edge
    SETB IT1                ; Trigger INT1 on falling edge
    SETB EX0                ; Enable SW1
    SETB EX1                ; Enable SW4
    SETB EA                 ; Enable Global Interrupts

    MOV TMOD, #01H          ; Timer 0 Mode 1 (Servo)
    MOV SEG_PORT, #00H      
    CLR DIS0
    CLR DIS1

    ; Initial States
    MOV CYCLE_COUNT, #0
    MOV UI_STATE, #0        ; Start at Menu
    MOV MOTOR_EN, #0        ; Motor off initially
    MOV UI_DIRTY, #1        ; Draw menu on boot

    ACALL INIT_LCD
    ACALL STARTUP_SEQ       ; Play welcome message ONCE

; =========================================================
; THE SUPER LOOP
; =========================================================
SUPER_LOOP:

    ; -----------------------------------------------------
    ; PART 1: INSTANT UI SCREEN MANAGER
    ; -----------------------------------------------------
    MOV A, UI_DIRTY
    JZ CHECK_KEYPAD         ; If screen is up to date, skip LCD drawing

    MOV UI_DIRTY, #0        ; Clear the flag
    ACALL LCD_CLEAR

    MOV A, UI_STATE
    CJNE A, #0, CHK_UI_1
    ; --- Draw State 0: MENU ---
    MOV DPTR, #STR_MENU1    
    ACALL WRITE_STRING
    ACALL LCD_LINE2
    MOV DPTR, #STR_MENU2    
    ACALL WRITE_STRING
    SJMP CHECK_KEYPAD

CHK_UI_1:
    CJNE A, #1, CHK_UI_2
    ; --- Draw State 1: CONFIRM MODE ---
    MOV DPTR, #STR_MODE     
    ACALL WRITE_STRING
    MOV A, TEMP_SPEED       
    ADD A, #'0'             
    ACALL LCD_DATA          
    MOV DPTR, #STR_SEL      
    ACALL WRITE_STRING
    ACALL LCD_LINE2
    MOV DPTR, #STR_CONFIRM  
    ACALL WRITE_STRING
    SJMP CHECK_KEYPAD

CHK_UI_2:
    CJNE A, #2, CHK_UI_3
    ; --- Draw State 2: START OR RESET? ---
    MOV DPTR, #STR_START_Q  
    ACALL WRITE_STRING
    ACALL LCD_LINE2
    MOV DPTR, #STR_START_A  
    ACALL WRITE_STRING
    SJMP CHECK_KEYPAD

CHK_UI_3:
    CJNE A, #3, CHK_UI_4
    ; --- Draw State 3: RUNNING ---
    MOV DPTR, #STR_MODE     
    ACALL WRITE_STRING
    MOV A, SPEED_MODE       
    ADD A, #'0'             
    ACALL LCD_DATA          
    ACALL LCD_LINE2
    MOV DPTR, #STR_RUN      
    ACALL WRITE_STRING
    SJMP CHECK_KEYPAD

CHK_UI_4:
    CJNE A, #4, CHK_UI_5
    ; --- Draw State 4: STOPPED ---
    MOV DPTR, #STR_STOP     
    ACALL WRITE_STRING
    SJMP CHECK_KEYPAD

CHK_UI_5:
    ; --- Draw State 5: DONE ---
    MOV DPTR, #STR_DONE     
    ACALL WRITE_STRING


    ; -----------------------------------------------------
    ; PART 2: NON-BLOCKING KEYPAD LOGIC
    ; -----------------------------------------------------
CHECK_KEYPAD:
    MOV A, UI_STATE
    CJNE A, #0, TRY_KEY_ST1
    
    ; --- Logic for State 0 (Menu) ---
    ACALL READ_KEYPAD_FAST
    CJNE A, #0FFH, EVAL_ST0 
    SJMP RUN_MOTOR          ; If no key, quickly skip to motor!
EVAL_ST0:
    CJNE A, #'0', C_K1
    SJMP ST0_VALID
C_K1: CJNE A, #'1', C_K2
    SJMP ST0_VALID
C_K2: CJNE A, #'2', C_K3
    SJMP ST0_VALID
C_K3: CJNE A, #'3', RUN_MOTOR 
ST0_VALID:
    CLR C
    SUBB A, #'0'            
    MOV TEMP_SPEED, A       
    MOV UI_STATE, #1        ; Go to State 1 (Confirm)
    MOV UI_DIRTY, #1
    LJMP SUPER_LOOP         

TRY_KEY_ST1:
    CJNE A, #1, TRY_KEY_ST2   
    
    ; --- Logic for State 1 (Confirm) ---
    ACALL READ_KEYPAD_FAST
    CJNE A, #0FFH, EVAL_ST1
    SJMP RUN_MOTOR
EVAL_ST1:
    CJNE A, #'A', CHK_B1    ; A = CONFIRM
    MOV UI_STATE, #2        ; Go to State 2 (Start or Reset)
    MOV UI_DIRTY, #1
    LJMP SUPER_LOOP         
CHK_B1:
    CJNE A, #'B', RUN_MOTOR ; B = RESET
    MOV UI_STATE, #0        ; Go back to Menu
    MOV UI_DIRTY, #1
    LJMP SUPER_LOOP         

TRY_KEY_ST2:
    CJNE A, #2, RUN_MOTOR
    
    ; --- Logic for State 2 (Start Menu) ---
    ACALL READ_KEYPAD_FAST
    CJNE A, #0FFH, EVAL_ST2
    SJMP RUN_MOTOR
EVAL_ST2:
    CJNE A, #'A', CHK_B2    ; A = START
    MOV SPEED_MODE, TEMP_SPEED
    MOV CYCLE_COUNT, #0     ; Reset counter exactly here
    MOV MOTOR_EN, #1        ; ENABLE THE MOTOR!
    MOV UI_STATE, #3        ; Go to Running screen
    MOV UI_DIRTY, #1
    LJMP SUPER_LOOP         
CHK_B2:
    CJNE A, #'B', RUN_MOTOR ; B = RESET
    MOV UI_STATE, #0        ; Go back to Menu
    MOV UI_DIRTY, #1
    LJMP SUPER_LOOP


    ; -----------------------------------------------------
    ; PART 3: MOTOR EXECUTION (WITH BREAKABLE DELAYS)
    ; -----------------------------------------------------
RUN_MOTOR:
    MOV A, MOTOR_EN
    JZ SUPER_LOOP_END       ; If MOTOR_EN is 0, SKIP servo execution!

    MOV A, SPEED_MODE
    CJNE A, #0, SP_1
    MOV R2, #150            ; Speed 0
    SJMP DO_MOVE
SP_1: CJNE A, #1, SP_2
    MOV R2, #125            ; Speed 1
    SJMP DO_MOVE
SP_2: CJNE A, #2, SP_3
    MOV R2, #100            ; Speed 2
    SJMP DO_MOVE
SP_3: MOV R2, #50           ; Speed 3

DO_MOVE:
    MOV A, R2
    MOV R3, A               
H_180:
    ; --- BREAKABLE CHECK ---
    MOV A, MOTOR_EN
    JZ ABORT_CYCLE          
    MOV A, UI_DIRTY
    JNZ ABORT_CYCLE         
    ; -----------------------
    ACALL SERVO_180
    DJNZ R3, H_180

    MOV A, R2
    MOV R3, A               
H_0:
    ; --- BREAKABLE CHECK ---
    MOV A, MOTOR_EN
    JZ ABORT_CYCLE          
    MOV A, UI_DIRTY
    JNZ ABORT_CYCLE         
    ; -----------------------
    ACALL SERVO_0
    DJNZ R3, H_0

    INC CYCLE_COUNT         
    
    MOV A, CYCLE_COUNT
    CJNE A, #10, SUPER_LOOP_END
    
    ; ==============================================================
    ; OPTION 1 FIX: Reached 10 cycles, INSTANT RETURN TO MENU!
    ; ==============================================================
    MOV MOTOR_EN, #0        
    MOV UI_STATE, #0        ; Change directly to State 0 (Menu) instead of State 5
    MOV UI_DIRTY, #1        
    SJMP SUPER_LOOP_END

ABORT_CYCLE:
    ; Jump here if button pressed mid-swing.

SUPER_LOOP_END:
    ACALL UPDATE_DISPLAY    
    LJMP SUPER_LOOP         


; ===================================================================
; NON-BLOCKING KEYPAD SCANNER
; ===================================================================
READ_KEYPAD_FAST:
    MOV KEY_PORT, #0F0H
    NOP
    NOP
    MOV A, KEY_PORT
    ANL A, #0F0H
    CJNE A, #0F0H, DO_SCAN
    MOV A, #0FFH            
    RET
DO_SCAN:
    ACALL DELAY_20MS        
    MOV R0, #0              
    MOV R1, #11111110B      
R_LOOP:
    MOV KEY_PORT, R1        
    NOP                     
    NOP
    MOV A, KEY_PORT         
    JNB ACC.7, K_MATCH  
    INC R0                  
    JNB ACC.6, K_MATCH  
    INC R0
    JNB ACC.5, K_MATCH  
    INC R0
    JNB ACC.4, K_MATCH  
    INC R0
    MOV A, R1
    RL A                    
    MOV R1, A
    CJNE R0, #16, R_LOOP  
    MOV A, #0FFH            
    RET         
K_MATCH:
    MOV DPTR, #KEY_MAP
    MOV A, R0
    MOVC A, @A+DPTR
    MOV R4, A               
W_REL:
    MOV KEY_PORT, #0F0H
    NOP
    NOP
    MOV A, KEY_PORT               
    ANL A, #0F0H            
    CJNE A, #0F0H, W_REL 
    ACALL DELAY_20MS        
    MOV A, R4               
    RET


; ===================================================================
; SERVO & 7-SEGMENT MODULES
; ===================================================================
SERVO_180:
    SETB SERVO_PIN      
    MOV TH0, #0F6H      
    MOV TL0, #0A0H
    SETB TR0            
W_H_180: 
    JNB TF0, W_H_180    
    CLR TR0
    CLR TF0
    CLR SERVO_PIN       
    MOV TH0, #0BBH      
    MOV TL0, #40H
    SETB TR0            
W_L_180: 
    ACALL UPDATE_DISPLAY 
    JNB TF0, W_L_180    
    CLR TR0
    CLR TF0
    RET

SERVO_0:
    SETB SERVO_PIN      
    MOV TH0, #0FEH      
    MOV TL0, #0CH
    SETB TR0            
W_H_0: 
    JNB TF0, W_H_0      
    CLR TR0
    CLR TF0
    CLR SERVO_PIN       
    MOV TH0, #0B3H      
    MOV TL0, #0D4H
    SETB TR0            
W_L_0: 
    ACALL UPDATE_DISPLAY 
    JNB TF0, W_L_0      
    CLR TR0
    CLR TF0
    RET

UPDATE_DISPLAY:
    MOV A, CYCLE_COUNT  
    MOV B, #10
    DIV AB              
    MOV DPTR, #SEG_TABLE
    MOVC A, @A+DPTR     
    MOV SEG_PORT, A     
    SETB DIS1           
    CLR DIS0            
    ACALL DELAY_40US   
    CLR DIS1            
    MOV A, B            
    MOVC A, @A+DPTR     
    MOV SEG_PORT, A     
    SETB DIS0           
    CLR DIS1            
    ACALL DELAY_40US   
    CLR DIS0            
    RET


; ===================================================================
; LCD MODULE
; ===================================================================
INIT_LCD:
    ACALL DELAY_50MS
    MOV A, #38H
    ACALL LCD_CMD
    ACALL DELAY_5MS
    MOV A, #38H
    ACALL LCD_CMD
    ACALL DELAY_5MS
    MOV A, #38H
    ACALL LCD_CMD
    ACALL DELAY_5MS
    MOV A, #0CH             
    ACALL LCD_CMD
    MOV A, #01H             
    ACALL LCD_CMD
    ACALL DELAY_5MS
    MOV A, #06H             
    ACALL LCD_CMD
    RET

STARTUP_SEQ:
    ACALL LCD_CLEAR
    MOV DPTR, #STR_HELLO
    ACALL WRITE_STRING
    ACALL LCD_LINE2
    MOV DPTR, #STR_WELCOME
    ACALL WRITE_STRING
    ACALL DELAY_2S_SOFT
    
    ACALL LCD_CLEAR
    MOV DPTR, #STR_GROUP
    ACALL WRITE_STRING
    ACALL LCD_LINE2
    MOV DPTR, #STR_NAME1
    ACALL WRITE_STRING
    ACALL DELAY_2S_SOFT
    
    ACALL LCD_CLEAR
    MOV DPTR, #STR_NAME2
    ACALL WRITE_STRING
    ACALL LCD_LINE2
    MOV DPTR, #STR_NAME3
    ACALL WRITE_STRING
    ACALL DELAY_2S_SOFT
    RET

WRITE_STRING:
    CLR A
    MOVC A, @A+DPTR
    JZ END_WRITE
    ACALL LCD_DATA
    INC DPTR
    SJMP WRITE_STRING
END_WRITE:
    RET

LCD_CLEAR:
    MOV A, #01H
    ACALL LCD_CMD
    ACALL DELAY_5MS
    RET

LCD_LINE2:
    MOV A, #0C0H
    ACALL LCD_CMD
    RET

LCD_CMD:
    MOV LCD_DAT, A
    CLR LCD_RS
    CLR LCD_RW
    SETB LCD_EN
    NOP
    NOP
    CLR LCD_EN
    ACALL DELAY_2MS
    RET

LCD_DATA:
    MOV LCD_DAT, A
    SETB LCD_RS
    CLR LCD_RW
    SETB LCD_EN
    NOP
    NOP
    CLR LCD_EN
    ACALL DELAY_2MS
    RET


; ===================================================================
; DELAY SUBROUTINES
; ===================================================================
DELAY_40US:
    MOV R7, #20
    DJNZ R7, $
    RET
DELAY_2MS:
    MOV R6, #4
D2_1: MOV R7, #250
D2_2: DJNZ R7, D2_2
    DJNZ R6, D2_1
    RET
DELAY_5MS:
    MOV R6, #10
D5_1: MOV R7, #250
D5_2: DJNZ R7, D5_2
    DJNZ R6, D5_1
    RET
DELAY_20MS:
    MOV R6, #40
D20_1: MOV R7, #250
D20_2: DJNZ R7, D20_2
    DJNZ R6, D20_1
    RET
DELAY_50MS:
    MOV R5, #100
D50_1: MOV R6, #250
D50_2: DJNZ R6, D50_2
    DJNZ R5, D50_1
    RET
DELAY_1S_SOFT:
    MOV R5, #10
D1S_1: MOV R6, #200
D1S_2: MOV R7, #250
D1S_3: DJNZ R7, D1S_3
    DJNZ R6, D1S_2
    DJNZ R5, D1S_1
    RET
DELAY_2S_SOFT:
    ACALL DELAY_1S_SOFT
    ACALL DELAY_1S_SOFT
    RET


; ===================================================================
; ROM STRINGS & TABLES
; ===================================================================
SEG_TABLE:
    DB 3FH, 06H, 5BH, 4FH, 66H, 6DH, 7DH, 07H, 7FH, 67H  

KEY_MAP: 
    DB '0','1','2','3'  
    DB '4','5','6','7'  
    DB '8','9','A','B'  
    DB 'C','D','E','F'

STR_HELLO:   DB 'H','E','L','L','O', 0
STR_WELCOME: DB 'W','e','l','c','o','m','e','!', 0
STR_GROUP:   DB 'G','r','o','u','p',' ','M','e','m','b','e','r','s',':', 0
STR_NAME1:   DB 'L','i','m',' ','C','h','u','n',' ','S','i','n', 0
STR_NAME2:   DB 'Y','o','n','g',' ','W','e','i',' ','S','h','e','n','g', 0
STR_NAME3:   DB 'S','h','a','w','n', 0

STR_MENU1:   DB 'S','e','l','e','c','t',' ','S','p','e','e','d', 0
STR_MENU2:   DB '0',' ',' ',' ','1',' ',' ',' ','2',' ',' ',' ','3', 0
STR_MODE:    DB 'M','o','d','e',' ', 0
STR_SEL:     DB ' ','S','e','l','e','c','t','e','d', 0
STR_CONFIRM: DB 'A','=','C','n','f','i','r','m',' ','B','=','R','e','s','e','t', 0
STR_START_Q: DB 'S','t','a','r','t',' ','o','r',' ','R','e','s','e','t','?', 0
STR_START_A: DB 'A','=','S','t','a','r','t',' ','B','=','R','e','s','e','t', 0
STR_RUN:     DB 'R','u','n','n','i','n','g','.','.','.', 0
STR_DONE:    DB 'C','o','m','p','l','e','t','e','!', 0
STR_STOP:    DB 'E','M','E','R','G','E','N','C','Y',' ','S','T','O','P', 0

    END