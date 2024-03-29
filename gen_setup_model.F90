! 1) read namelist files
! 2) determine time step size
! 3) handling model parameters
! 4) define prognostic tracers
! 5) get the number of iteration to run

subroutine setup_model
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------------

  implicit none

  call read_namelist            ! Read Namelists, this should be before clock_init
  call calculate_time_step      ! time step size
  call pre_handling_parameters  ! such as transform units 
  call define_prog_tracer

end subroutine setup_model
!
!-------------------------------------------------------------------
!
subroutine read_namelist
  ! Routine reads namelist files to overwrite default parameters.
  !
  ! Coded by Lars Nerger
  ! Modified by Qiang Wang to have more separated namelist files
  ! Reviewed by ??
  !--------------------------------------------------------------

  use g_config
  use o_param
  use i_dyn_parms
  use i_therm_parms
  use g_diag
  use g_forcing_param
  use g_parfe
  use g_clock, only: timenew, daynew, yearnew
  implicit none

  character(len=100)   :: nmlfile
  namelist /clockinit/ timenew, daynew, yearnew

  nmlfile ='namelist.config'    ! name of general configuration namelist file
  open (20,file=nmlfile)
  read (20,NML=modelname)
  read (20,NML=timestep)
  read (20,NML=clockinit) 
  read (20,NML=paths)
  read (20,NML=initialization)  
  read (20,NML=inout)
  read (20,NML=mesh_def)
  read (20,NML=geometry)
  read (20,NML=calendar)
  close (20)

  nmlfile ='namelist.oce'    ! name of ocean namelist file
  open (20,file=nmlfile)
  read (20,NML=viscdiff)
  read (20,NML=boundary)
  read (20,NML=oce_scheme)
  read (20,NML=denspress)
  read (20,NML=param_freesurf)
  read (20,NML=tide_obc)
  read (20,NML=passive_tracer)
  read (20,NML=age_tracer)
  read (20,NML=tracer_cutoff)
  close (20)

  nmlfile ='namelist.forcing'    ! name of forcing namelist file
  open (20,file=nmlfile)
  read (20,NML=forcing_exchange_coeff)
  read (20,NML=forcing_source)
  read (20,NML=forcing_bulk)
  read (20,NML=land_ice)
  close (20)

#ifdef use_ice
  nmlfile ='namelist.ice'    ! name of ice namelist file
  open (20,file=nmlfile)
  read (20,NML=ice_stress)
  read (20,NML=ice_fric)
  read (20,NML=ice_rheology)
  read (20,NML=ice_scheme)
  read (20,NML=ice_therm)
  close (20)
#endif

  nmlfile='namelist.diag'    ! name of diagnose namelist file
  open(20, file=nmlfile)
  read(20,NML=diag_flag)
  close(20)

  if(mype==0) then 
   write(*,*) 'Namelist files are read in'
   write(*,*) 'PP_max_mix_coeff=', PP_max_mix_coeff
  endif
end subroutine read_namelist
!
!-------------------------------------------------------------------
!
subroutine calculate_time_step
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------------
  
  use g_config
  use g_parfe
  implicit none

  ! compute dt and dt_inv
  dt=86400./float(step_per_day)
  dt_inv=1.0/dt    
  if(mype==0) write(*,*) 'time step size is set to ', real(dt,4), 'sec'

end subroutine calculate_time_step
!
!-------------------------------------------------------------------
!
subroutine pre_handling_parameters
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------------
  
  use o_param
  use g_config
  use g_parfe
  implicit none

  ! change parameter unit: degree to radian
  domain_length=domain_length*rad
  if(rotated_grid) then 
     alphaEuler=alphaEuler*rad 	
     betaEuler=betaEuler*rad
     gammaEuler=gammaEuler*rad
  end if

end subroutine pre_handling_parameters
!
!-------------------------------------------------------------------
!
subroutine define_prog_tracer
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------------
  
  use o_param
  use o_array, only : prog_tracer_name
  use g_parfe
  implicit none

  integer      :: j, num
  character(1) :: cageind
  character(4) :: tr_name

  ! allocate prog_tracer_name

  num_tracer=2  ! t and s
  if(use_passive_tracer) then
     num_tracer=num_tracer+num_passive_tracer
  end if
  if(use_age_tracer) then
     num_tracer=num_tracer+num_age_tracer
  end if

  allocate(prog_tracer_name(num_tracer))

  ! fill prog_tracer_name

  num=2  ! t and s

  prog_tracer_name(1)='temp'
  prog_tracer_name(2)='salt'

  if(use_passive_tracer) then
     do j=1,num_passive_tracer
        write(cageind,'(i1)') j
        tr_name='ptr'//cageind
	prog_tracer_name(num+j)=tr_name
     end do
     num=num+num_passive_tracer
  end if

  if(use_age_tracer) then
     do j=1,num_age_tracer
        write(cageind,'(i1)') j
        tr_name='age'//cageind
	prog_tracer_name(num+j)=tr_name
     end do
     num=num+num_age_tracer
  end if

  if(mype==0) write(*,*) 'Number of prognostic ocean tracers: num, num_tracer',num,num_tracer

end subroutine define_prog_tracer
!
!-------------------------------------------------------------------
!
subroutine get_run_steps
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------------
  
  use g_config
  use g_clock
  use g_parfe
  implicit none

  integer      :: i, temp_year, temp_mon, temp_fleapyear

  ! clock should have been inialized before calling this routine

  if(run_length_unit=='s') then
     nsteps=run_length
  elseif(run_length_unit=='d') then
     nsteps=step_per_day*run_length
  elseif(run_length_unit=='m') then
     nsteps=0
     temp_mon=month-1
     temp_year=yearnew
     temp_fleapyear=fleapyear
     do i=1,run_length
        temp_mon=temp_mon+1
        if(temp_mon>12) then
           temp_year=temp_year+1
           temp_mon=1
           call check_fleapyr(temp_year, temp_fleapyear)
        end if
        nsteps=nsteps+step_per_day*num_day_in_month(temp_fleapyear,temp_mon)
     end do
  elseif(run_length_unit=='y') then
     nsteps=0
     do i=1,run_length
        temp_year=yearnew+i-1
        call check_fleapyr(temp_year, temp_fleapyear)
!rt        nsteps=nsteps+step_per_day*(365+temp_fleapyear)
        nsteps=nsteps+step_per_day*(ndpyr0+temp_fleapyear)   !RT RG45981 19.06.20
     end do
  else
     write(*,*) 'Run length unit ', run_length_unit, ' is not defined.'
     write(*,*) 'Please check and update the code.'
     call par_ex
     stop
  end if

  if(mype==0) write(*,*) nsteps, ' steps to run for this (', runid, ') job submission'
end subroutine get_run_steps
