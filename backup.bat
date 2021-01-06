:: Minecraft server automatic backup script
:: by Nicolas Chan, adapted by Ted Grosson
:: MIT License
:: 
:: For Minecraft servers running on Windows in a GNU screen
:: For text output to Minecraft server chat, this script requires installation of screen or tmux through e.g. Cygwin
::
:: For most convenience, run automatically with schtasks

@echo off

:: Default configuration
set SCREEN_NAME= &::Name of the GNU Screen or tmux pane server is running in
set SERVER_WORLD= &::Server world directory
set BACKUP_DIRECTORY= &:: Directory to save backups in
set /a MAX_BACKUPS=128 &:: -1 indicates unlimited
set DELETE_METHOD=thin &::Choices: thin, sequential, none; sequential: delete oldest; thin: Keep last 24 hourly, last 30 daily, and monthly (use with 1 hr cron interval)
set COMPRESSION_ALGORITHM=gzip&::Leave empty for no compression
set COMPRESSION_FILE_EXTENSION=.gz&::Leave empty for no compression; Precede with a . (for example: ".gz")
set /a COMPRESSION_LEVEL=3 &::Passed to the compression algorithm
::ENABLE_CHAT_MESSAGES set to false
set PREFIX=Backup &::Shows in the chat message
::DEBUG set to false
::SUPPRESS_WARNINGS set to false
set WINDOW_MANAGER=screen &::Choices: screen, tmux

:: Get timestamp in format YYYY-mm-dd_HH-MM_a
set mydate=%DATE:~10,4%-%DATE:~4,2%-%DATE:~7,2%
set mytime=%TIME:~0,2%-%TIME:~3,2%
set dayofweek=%DATE:~0,3%
set TIMESTAMP=%mydate%_%mytime%_%dayofweek%

:GETOPTS
	if /I "%1" == "-a" set COMPRESSION_ALGORITHM=%2& shift
	if /I "%1" == "-c" set ENABLE_CHAT_MESSAGES=1
	if /I "%1" == "-d" set DELETE_METHOD=%2& shift
	if /I "%1" == "-e" set COMPRESSION_FILE_EXTENSION=.%2& shift
	if /I "%1" == "-f" set TIMESTAMP=%2& shift
	if /I "%1" == "-h" goto HELP
	if /I "%1" == "-i" set SERVER_WORLD=%2& shift
	if /I "%1" == "-l" set COMPRESSION_LEVEL=%2& shift
	if /I "%1" == "-m" set MAX_BACKUPS=%2& shift
	if /I "%1" == "-o" set BACKUP_DIRECTORY=%2& shift
	if /I "%1" == "-p" set PREFIX=%2& shift
	if /I "%1" == "-q" set SUPPRESS_WARNINGS=1
	if /I "%1" == "-s" set SCREEN_NAME=%2& shift
	if /I "%1" == "-v" set DEBUG=1
	if /I "%1" == "-w" set WINDOW_MANAGER=%2& shift
	shift
if not "%1" == "" goto GETOPTS

	
:: Check for missing encouraged arguments
if not defined SUPPRESS_WARNINGS (
	if not defined SCREEN_NAME (
		CALL :log-warning "Minecraft screen name not specified (use -s)"
	)
)

:: Check for required arguments
if not defined SERVER_WORLD (
	CALL :log-fatal "Server world not specified (use -i)"
)
if not defined BACKUP_DIRECTORY (
	CALL :log-fatal "Backup directory not specified (use -o)"
)

set ARCHIVE_FILE_NAME=%TIMESTAMP%.tar%COMPRESSION_FILE_EXTENSION%
set ARCHIVE_PATH=%BACKUP_DIRECTORY%\%ARCHIVE_FILE_NAME%

:: Notify players of start
CALL :message-players "Starting backup..." "%ARCHIVE_FILE_NAME%"

:: Disable world autosaving
CALL :execute-command "save-off"

:: Backup world
if not defined COMPRESSION_ALGORITHM (
	tar -cf %ARCHIVE_PATH% -C %SERVER_WORLD% .
) ELSE (
	tar -cf - -C %SERVER_WORLD% . | %COMPRESSION_ALGORITHM% -cv -%COMPRESSION_LEVEL% - > %ARCHIVE_PATH% 2>>NUL
)

:: Enable world autosaving
CALL :execute-command "save-on"

:: Save the world
CALL :execute-command "save-all"

:: Notify players of completion
set WORLD_SIZE_BYTES=0
FOR /R %SERVER_WORLD% %%x in (*) do set /a WORLD_SIZE_BYTES+=%%~zx
FOR %%x in (%ARCHIVE_PATH%) do set ARCHIVE_SIZE_BYTES=%%~zx
set /a COMPRESSION_PERCENT=(ARCHIVE_SIZE_BYTES*100/WORLD_SIZE_BYTES)
set BACKUP_DIRECTORY_SIZE=0
FOR /R %BACKUP_DIRECTORY% %%x in (*) do set /a BACKUP_DIRECTORY_SIZE+=%%~zx
:: Check that archive size is at least 1 KB
if ARCHIVE_SIZE_BYTES geq 1024 (
	CALL :message-players-success "Backup complete!" "%ARCHIVE_SIZE_BYTES%/%BACKUP_DIRECTORY_SIZE%, %COMPRESSION_PERCENT%%%"
	CALL :delete-old-backups
) else (
	CALL :message-players-error "Backup was not saved!" "Please notify an administrator"
)

EXIT /B %ERRORLEVEL%



:HELP
	echo Minecraft Backup (by Nicolas Chan, adapted by Ted Grosson)
	echo -a   Compression algorithm (default: gzip)
	echo -c   Enable chat messages
	echo -d   Delete method: thin (default), sequential, none
	echo -e   Compression file extension, exculde leading \".\" (default: gz)
	echo -f   Output file name (default is the timestamp)
	echo -h   Shows this help text
	echo -i   Input directory (path to world folder)
	echo -l   Compression level (default: 3)
	echo -m   Maximum backups to keep, use -1 for unlimited (default: 128)
	echo -o   Output directory
	echo -p   Prefix that shows in Minecraft chat (default: Backup)
	echo -q   Suppress warnings
	echo -s   Minecraft server screen name
	echo -v   Verbose mode
	echo -w   Window manager: screen (default) or tmux
	goto :EOF

:log-fatal	
	echo [91mFATAL:[0m %~1
	goto :EOF
	EXIT /B 0

:log-warning
	echo [93mWARNING:[0m %~1
	EXIT /B 0
	
:: Minecraft server screen interface functions
:message-players
	SETLOCAL
	set MESSAGE=%~1
	set HOVER_MESSAGE=%~2
	CALL :message-players-color "%MESSAGE%", "%HOVER_MESSAGE%", "gray"
	ENDLOCAL
	EXIT /B 0
:execute-command
	SETLOCAL
	set COMMAND=%~1
	if "%SCREEN_NAME%"=="screen" (
		screen -S %SCREEN_NAME% -p 0 -X stuff "/%COMMAND%\\r"
	)
	if "%SCREEN_NAME%"=="tmux" (
		tmux send-keys -t %SCREEN_NAME% "%COMMAND%" ENTER
	)
	ENDLOCAL
	EXIT /B 0
:message-players-error
	SETLOCAL
	set MESSAGE=%~1
	set HOVER_MESSAGE=%~2
	CALL :message-players-color "%MESSAGE%", "%HOVER_MESSAGE%", "red"
	ENDLOCAL
	EXIT /B 0
:message-players-success
	SETLOCAL
	set MESSAGE=%~1
	set HOVER_MESSAGE=%~2
	CALL :message-players-color "%MESSAGE%", "%HOVER_MESSAGE%", "green"
	ENDLOCAL
	EXIT /B 0
:message-players-color
	SETLOCAL
	set MESSAGE=%~1
	set HOVER_MESSAGE=%~2
	set COLOR=%~3
	if defined DEBUG echo %MESSAGE% (%HOVER_MESSAGE%)
	if defined ENABLE_CHAT_MESSAGES (
		CALL :execute-command "tellraw @a [\"\",{\"text\":\"[%PREFIX%] \",\"color\":\"gray\",\"italic\":true},{\"text\":\"%MESSAGE%\",\"color\":\"%COLOR%\",\"italic\":true,\"hoverEvent\":{\"action\":\"show_text\",\"value\":{\"text\":\"\",\"extra\":[{\"text\":\"%HOVER_MESSAGE%\"}]}}}]"
	)
	ENDLOCAL
	EXIT /B 0

:: Delete a backup
:delete-backup
	SETLOCAL
	set BACKUP=%~1
	del %BACKUP_DIRECTORY%\%BACKUP%
	CALL :message-players "Deleted old backup" "%BACKUP%"
	ENDLOCAL
	EXIT /B 0

:: Sequential delete method
:delete-sequentially
	SETLOCAL EnableDelayedExpansion
	if %MAX_BACKUPS% geq 0 (
		:while1
		set i=0
		for %%a in (*.tar*) do (
			set /a i+=1
			set BACKUPS[!i!]=%%a
		)
		set NUMBER_BACKUPS=%i%
	
		if %NUMBER_BACKUPS% gtr %MAX_BACKUPS% (
			CALL :delete-backup %BACKUPS[1]%
		)
		
		if %NUMBER_BACKUPS%-1 gtr %MAX_BACKUPS% goto :while1
	)
	ENDLOCAL
	EXIT /B 0

:: Functions to sort backups into correct categories based on timestamps
:is-hourly-backup
	SETLOCAL
	set TIMESTAMP=%~1
	set %~2=%TIMESTAMP:~14,2%==00
	ENDLOCAL
	EXIT /B 0
:is-daily-backup
	SETLOCAL
	set TIMESTAMP=%~1
	set %~2=%TIMESTAMP:~11,2%==00
	ENDLOCAL
	EXIT /B 0
:is-weekly-backup
	SETLOCAL
	set TIMESTAMP=%~1
	set %~2=%TIMESTAMP:~17,3%==Mon
	ENDLOCAL
	EXIT /B 0

:: Thinning delete method
:delete-thinning
	SETLOCAL EnableDelayedExpansion
	:: sub-hourly, hourly, daily, weekly is everything else
	set BLOCK_SIZES[1]=16
	set BLOCK_SIZES[2]=24
	set BLOCK_SIZES[3]=30
	:: First block is unconditional
	:: The next blocks will only accept files whose names cause these functions to return true (0)
	set BLOCK_FUNCTIONS[1]=CALL :is-hourly-backup
	set BLOCK_FUNCTIONS[2]=CALL :is-daily-backup
	set BLOCK_FUNCTIONS[3]=CALL :is-weekly-backup
	
	:: Warn if %MAX_BACKUPS% does not have enough room for all the blocks
	set /a TOTAL_BLOCK_SIZE=BLOCK_SIZES[1]+BLOCK_SIZES[2]+BLOCK_SIZES[3]
	if %MAX_BACKUPS% geq 0 (
		if %TOTAL_BLOCK_SIZE% gt %MAX_BACKUPS% (
			if not defined SUPPRESS_WARNINGS (
				CALL :log-warning "MAX_BACKUPS (%MAX_BACKUPS%) is smaller than TOTAL_BLOCK_SIZE (%TOTAL_BLOCK_SIZE%)"
			)
		)
	)
	
	set CURRENT_INDEX=1
	:: List newest backups first
	set i=0
	for /f "tokens=*" %%a in ('dir /b /o-n') do (
		set /a i+=1
		set BACKUPS[!i!]=%%a
	)
	set NUMBER_BACKUPS=%i%
	
	for /L %%x in (1,1,3) do (
		set BLOCK_SIZE=!BLOCKSIZES[%%x]!
		set BLOCK_FUNCTION=!BLOCK_FUNCTIONS[%%x]!
		set /a OLDEST_BACKUP_IN_BLOCK_INDEX=BLOCK_SIZE+CURRENT_INDEX &::Not an off-by-one error because a new backup was already saved
		set OLDEST_BACKUP_IN_BLOCK=!BACKUPS[%OLDEST_BACKUP_IN_BLOCK_INDEX%]!
		
		:: If block isn't full yet, break
		if not defined OLDEST_BACKUP_IN_BLOCK goto :break1
		
		set OLDEST_BACKUP_TIMESTAMP=%OLDEST_BACKUP_IN_BLOCK:~0,20%
		%BLOCK_FUNCTION% "%OLDEST_BACKUP_TIMESTAMP%" "BLOCK_COMMAND"
		
		if %BLOCK_COMMAND% (
			:: Oldest backup in this block satisfies the condition for placement in the next block
			if defined DEBUG (echo %OLDEST_BACKUP_IN_BLOCK% promoted to next block)
		) else (
			:: Oldest backup in this block does not satisfy the condition for placement in next block
			CALL :delete-backup %OLDEST_BACKUP_IN_BLOCK%
			goto :break1
		)
		
		set /a CURRENT_INDEX+=BLOCK_SIZE
	)
	:break1
	
	CALL :delete-sequentially
	
	ENDLOCAL
	EXIT /B 0
	
:: Delete old backups
:delete-old-backups
	if /I "%DELETE_METHOD%"=="sequential" CALL :delete-sequentially
	if /I "%DELETE_METHOD%"=="thin" CALL :delete-thinning
	EXIT /B 0