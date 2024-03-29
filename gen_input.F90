! Routines for reading inital or re-start files

subroutine oce_input
  ! read restart fields for ocean dynamics and active tracer variables
  ! 
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !------------------------------------------------------------------
  
  use o_param
  use o_mesh
  use o_array
  use g_clock
  use g_config
  use g_PARFE
  implicit none

#include "netcdf.inc" 

  integer                   :: status, ncid, j, dimid_rec, nrec
  integer                   :: ssh_varid, tra_varid(2)
  integer                   :: u_varid, v_varid, w_varid, wpot_varid
  integer                   :: istart(2), icount(2), n3
  character(100)            :: filename
  character(1)              :: trind
  real(kind=8), allocatable :: aux2(:), aux3(:) 

  allocate(aux2(nod2D), aux3(nod3D)) 
  n3=ToDim_nod3D           

  ! open files
  filename=trim(ResultPath)//runid//'.'//cyearold//'.oce.ini.nc'
  status = nf_open(filename, nf_nowrite, ncid)
  if (status .ne. nf_noerr) call handle_err(status)

  ! inquire variable id
  status=nf_inq_varid(ncid, 'ssh', ssh_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'u', u_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'v', v_varid)
  if (status .ne. nf_noerr) call handle_err(status)
#ifdef use_non_hydrostatic
  status=nf_inq_varid(ncid, 'w', w_varid)
  if (status .ne. nf_noerr) call handle_err(status)
#else
  status=nf_inq_varid(ncid, 'wpot', wpot_varid)
  if (status .ne. nf_noerr) call handle_err(status)
#endif
  status=nf_inq_varid(ncid, 'temp', tra_varid(1))
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'salt', tra_varid(2))
  if (status .ne. nf_noerr) call handle_err(status)

  ! read variables

  ! which record to read
  if(restartflag=='last') then
     status = nf_inq_dimid(ncid, 'T', dimid_rec)
     if(status .ne. nf_noerr) call handle_err(status)
     status = nf_inq_dimlen(ncid, dimid_rec, nrec)
     if(status .ne. nf_noerr) call handle_err(status)
  else
     read(restartflag,'(i4)') nrec
  end if

  ! 2d fields
  istart=(/1,nrec/)
  icount=(/nod2d, 1/)
  status=nf_get_vara_double(ncid, ssh_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  ssh=aux2(myList_nod2D)         

  ! 3d fields
  istart=(/1,nrec/)
  icount=(/nod3d, 1/)

  status=nf_get_vara_double(ncid, u_varid, istart, icount, aux3)
  if (status .ne. nf_noerr) call handle_err(status)
  uf(1:n3)=aux3(myList_nod3D)     

  status=nf_get_vara_double(ncid, v_varid, istart, icount, aux3) 
  if (status .ne. nf_noerr) call handle_err(status)
  uf(1+n3:2*n3)=aux3(myList_nod3D)  

#ifdef use_non_hydrostatic
  status=nf_get_vara_double(ncid, w_varid, istart, icount, aux3) 
  uf(1+2*n3:3*n3)=aux3(myList_nod3D)
#else
  status=nf_get_vara_double(ncid, wpot_varid, istart, icount, aux3)
  w=aux3(myList_nod3D)             
#endif
  if (status .ne. nf_noerr) call handle_err(status)

  do j=1,2
   if(mype==0) write(*,*) 'oce_input: try to read data',j,ncid,tra_varid(j),istart,icount
   status=nf_get_vara_double(ncid, tra_varid(j), istart, icount, aux3) 
   if (status .ne. nf_noerr) call handle_err(status)
   tracer(:,j)=aux3(myList_nod3D)  
  end do

  status=nf_close(ncid)
  if (status .ne. nf_noerr) call handle_err(status)

  ! the next record to be saved
  save_count=nrec+1

  deallocate(aux3, aux2)   

end subroutine oce_input
!
!-------------------------------------------------------------------------
!
subroutine age_tracer_input
  ! 
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !------------------------------------------------------------------
  
  use o_param
  use o_mesh
  use o_array
  use o_age_tracer_mod
  use g_clock
  use g_config
  use g_PARFE
  implicit none

#include "netcdf.inc" 

  integer                   :: status, ncid, j, dimid_rec, nrec
  integer                   :: tra_varid(num_age_tracer)
  integer                   :: istart(2), icount(2), n3
  character(100)            :: filename
  character(1)              :: trind
  real(kind=8), allocatable :: aux3(:) 

  allocate(aux3(nod3D)) 
  n3=ToDim_nod3D           

  ! open files
  filename=trim(ResultPath)//runid//'.'//cyearold//'.oce.nc'
  status = nf_open(filename, nf_nowrite, ncid)
  if (status .ne. nf_noerr) call handle_err(status)

  ! inquire variable id
  do j=1,num_age_tracer 
     write(trind,'(i1)') j
     status=nf_inq_varid(ncid, 'age'//trind, tra_varid(j))
     if (status .ne. nf_noerr) call handle_err(status)
  end do

  ! read variables

  ! which record to read
  if(restartflag=='last') then
     status = nf_inq_dimid(ncid, 'T', dimid_rec)
     if(status .ne. nf_noerr) call handle_err(status)
     status = nf_inq_dimlen(ncid, dimid_rec, nrec)
     if(status .ne. nf_noerr) call handle_err(status)
  else
     read(restartflag,'(i4)') nrec
  end if

  ! 3d age tracer fields
  istart=(/1,nrec/)
  icount=(/nod3d, 1/)

  do j=1,num_age_tracer
     status=nf_get_vara_double(ncid, tra_varid(j), istart, icount, aux3) 
     if (status .ne. nf_noerr) call handle_err(status)
     tracer(:,index_age_tracer(j))=aux3(myList_nod3D)  
  end do

  status=nf_close(ncid)
  if (status .ne. nf_noerr) call handle_err(status)

  deallocate(aux3)   

end subroutine age_tracer_input
!
!-------------------------------------------------------------------------
!
subroutine passive_tracer_input
  ! 
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !------------------------------------------------------------------

  use o_param
  use o_mesh
  use o_array
  use o_age_tracer_mod
  use o_passive_tracer_mod
  use g_config
  use g_clock
  use g_PARFE
  implicit none

#include "netcdf.inc" 

  integer                   :: status, ncid, j, dimid_rec, nrec
  integer                   :: tra_varid(num_passive_tracer)
  integer                   :: istart(2), icount(2), n3
  character(100)            :: filename
  character(1)              :: trind
  real(kind=8), allocatable :: aux3(:) 

  allocate(aux3(nod3D)) 
  n3=ToDim_nod3D           

  ! open files
  filename=trim(ResultPath)//runid//'.'//cyearold//'.oce.nc'
  if(mype==0) write(*,*) 'passive_tracer_input: try to open',filename
  status = nf_open(filename, nf_nowrite, ncid)
  if (status .ne. nf_noerr) then
   write(*,*)'passive_tracer_input: file not found. filename=',filename
   stop
  endif


  ! inquire variable id
  do j=1,num_passive_tracer 
   write(trind,'(i1)') j
   if(mype==0) write(*,*) 'passive_tracer_input: try to get varid for ptr'//trind
   status=nf_inq_varid(ncid, 'ptr'//trind, tra_varid(j))
   if (status .ne. nf_noerr) then
    write(*,*)'passive_tracer_input: variable not found. variable= ptr'//trind
    stop
   endif
  end do

  ! read variables

  ! which record to read
  if(mype==0) write(*,*) 'passive_tracer_input: find out which record to read'
   if(restartflag=='last') then
   status = nf_inq_dimid(ncid, 'T', dimid_rec)
   if (status .ne. nf_noerr) then
    write(*,*)'passive_tracer_input: nf_inq_dimid failed'
    stop
   endif
   status = nf_inq_dimlen(ncid, dimid_rec, nrec)
   if (status .ne. nf_noerr) then
    write(*,*)'passive_tracer_input: nf_inq_dimlen failed'
    stop
   endif
     if(status .ne. nf_noerr) call handle_err(status)
  else
     read(restartflag,'(i4)') nrec
  end if

  ! 3d tracer fields
  istart=(/1,nrec/)
  icount=(/nod3d, 1/)

  do j=1,num_passive_tracer
   if(mype==0) write(*,*) 'passive_tracer_input: try to read data',j,ncid,tra_varid(j),istart,icount
   status=nf_get_vara_double(ncid, tra_varid(j), istart, icount, aux3) 
   if(mype==0) write(*,*) 'passive_tracer_input: succeeded to read data',tra_varid(j),istart,icount
   if (status .ne. nf_noerr) then
    write(*,*)'passive_tracer_input: nf_get_vara_double failed. ',tra_varid(j),istart,icount
   stop
   endif
   if(mype==0) write(*,*) 'passive_tracer_input: try to copy data into tracer field, index_passive_tracer(j)=',index_passive_tracer(j)
   tracer(:,index_passive_tracer(j))=aux3(myList_nod3D)  
   if(mype==0) write(*,*) 'passive_tracer_input: data reading completed, j=',j
  end do

  status=nf_close(ncid)
  if (status .ne. nf_noerr) then
   write(*,*)'passive_tracer_input: nf_close failed.'
   stop
  endif

  deallocate(aux3)   
  if(mype==0) write(*,*) 'passive_tracer_input succesfully completed'

end subroutine passive_tracer_input
!
!-------------------------------------------------------------------------
!
subroutine ice_input
  ! 
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !------------------------------------------------------------------

  use o_mesh
  use i_array
  use g_config
  use g_clock
  use g_PARFE
  implicit none

#include "netcdf.inc" 

  integer                   :: status, ncid, dimid_rec, nrec
  integer                   :: area_varid, hice_varid, hsnow_varid
  integer                   :: uice_varid, vice_varid
  integer                   :: istart(2), icount(2)
  character(100)            :: filename
  real(kind=8), allocatable :: aux2(:)

  allocate(aux2(nod2D))  

  ! open files
  filename=trim(ResultPath)//runid//'.'//cyearold//'.ice.ini.nc'
  status = nf_open(filename, nf_nowrite, ncid)
  if (status .ne. nf_noerr) call handle_err(status)

  ! inquire variable id
  status=nf_inq_varid(ncid, 'area', area_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'hice', hice_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'hsnow', hsnow_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'uice', uice_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'vice', vice_varid)
  if (status .ne. nf_noerr) call handle_err(status)

  ! read variables

  ! which record to read
  if(restartflag=='last') then
     status = nf_inq_dimid(ncid, 'T', dimid_rec)
     if(status .ne. nf_noerr) call handle_err(status)
     status = nf_inq_dimlen(ncid, dimid_rec, nrec)
     if(status .ne. nf_noerr) call handle_err(status)
  else
     read(restartflag,'(i4)') nrec
  end if

  istart=(/1,nrec/)
  icount=(/nod2d, 1/)
  status=nf_get_vara_double(ncid, area_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  a_ice=aux2(myList_nod2D)     
  status=nf_get_vara_double(ncid, hice_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  m_ice=aux2(myList_nod2D)      
  status=nf_get_vara_double(ncid, hsnow_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  m_snow=aux2(myList_nod2D)      
  status=nf_get_vara_double(ncid, uice_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  u_ice=aux2(myList_nod2D)      
  status=nf_get_vara_double(ncid, vice_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  v_ice=aux2(myList_nod2D)       
  status=nf_close(ncid)
  if (status .ne. nf_noerr) call handle_err(status)

  deallocate(aux2)   
end subroutine ice_input
!
!-------------------------------------------------------------------------
!
subroutine read_prepared_initial_ice
  ! 
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !------------------------------------------------------------------
  
  use o_mesh
  use i_array
  use g_config
  use g_clock
  use g_PARFE
  implicit none

#include "netcdf.inc" 

  integer                   :: status, ncid, dimid_rec, nrec
  integer                   :: area_varid, hice_varid, hsnow_varid
  integer                   :: uice_varid, vice_varid
  integer                   :: istart(2), icount(2)
  character(100)            :: filename
  real(kind=8), allocatable :: aux2(:)

  allocate(aux2(nod2D))  

  ! open files
  filename=trim(ResultPath)//runid//'.'//'initial_ice.nc'
  status = nf_open(filename, nf_nowrite, ncid)
  if (status .ne. nf_noerr) then
     print*,'ERROR: CANNOT READ initial ice FILE CORRECTLY !'
     print*,'Error in opening netcdf file'//filename
     call par_ex 
     stop
  endif
  
  ! inquire variable id
  status=nf_inq_varid(ncid, 'area', area_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'hice', hice_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  status=nf_inq_varid(ncid, 'hsnow', hsnow_varid)
  if (status .ne. nf_noerr) call handle_err(status)
  !status=nf_inq_varid(ncid, 'uice', uice_varid)
  !if (status .ne. nf_noerr) call handle_err(status)
  !status=nf_inq_varid(ncid, 'vice', vice_varid)
  !if (status .ne. nf_noerr) call handle_err(status)

  ! read variables

  ! which record to read
  if(restartflag=='last') then
     status = nf_inq_dimid(ncid, 'T', dimid_rec)
     if(status .ne. nf_noerr) call handle_err(status)
     status = nf_inq_dimlen(ncid, dimid_rec, nrec)
     if(status .ne. nf_noerr) call handle_err(status)
  else
     read(restartflag,'(i4)') nrec
  end if

  istart=(/1,nrec/)
  icount=(/nod2d, 1/)
  status=nf_get_vara_double(ncid, area_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  a_ice=aux2(myList_nod2D)     
  status=nf_get_vara_double(ncid, hice_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  m_ice=aux2(myList_nod2D)      
  status=nf_get_vara_double(ncid, hsnow_varid, istart, icount, aux2) 
  if (status .ne. nf_noerr) call handle_err(status)
  m_snow=aux2(myList_nod2D)      
  !status=nf_get_vara_double(ncid, uice_varid, istart, icount, aux2) 
  !if (status .ne. nf_noerr) call handle_err(status)
  !u_ice=aux2(myList_nod2D)      
  !status=nf_get_vara_double(ncid, vice_varid, istart, icount, aux2) 
  !if (status .ne. nf_noerr) call handle_err(status)
  !v_ice=aux2(myList_nod2D)       
  status=nf_close(ncid)
  if (status .ne. nf_noerr) call handle_err(status)

  deallocate(aux2)   

  !cutoff
  
  where(a_ice>1.0)
     a_ice=1.0
  end where

  where(a_ice<0.0)
     a_ice=0.0
  end where
  
  where(m_ice<0.0)
     m_ice=0.0
  end where

  where(m_snow<0.0)
     m_snow=0.0
  end where
  
  !u_ice=0.
  !v_ice=0.
  
end subroutine read_prepared_initial_ice
!
!-----------------------------------------------------------------------------
!
subroutine read_init_ts
  ! 
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !------------------------------------------------------------------

  use o_mesh
  use o_param
  use o_array
  use g_config
  use g_PARFE
  implicit none
  !
  integer                     :: i, j, n, n3
  integer                     :: num_lat_reg, num_lon_reg, num_lay_reg
  real(kind=8)                :: pp, pr, tt, ss, lon, lat, tbott, sbott
  real(kind=8), external      :: theta
  real(kind=8), allocatable   :: lon_reg(:), lat_reg(:), lay_reg(:)
  real(kind=8), allocatable   :: raw_data(:,:,:)
  real(kind=8), allocatable   :: temp_x(:), temp_y(:)

  ! open global T/S data files
  write(*,*)'open ',trim(ClimateDataPath)//trim(OceClimaDataName)
  open(19,file=trim(ClimateDataPath)//trim(OceClimaDataName), status='old')

  ! read reg. grid
  read(19,*) num_lon_reg, num_lat_reg, num_lay_reg
  allocate(lon_reg(num_lon_reg))
  allocate(lat_reg(num_lat_reg))
  allocate(lay_reg(num_lay_reg))
  read(19,*) lon_reg
  read(19,*) lat_reg
  read(19,*) lay_reg
  allocate(raw_data(num_lon_reg,num_lat_reg,num_lay_reg))

  ! model grid coordinates
  allocate(temp_x(myDim_nod3d+eDim_nod3D), temp_y(myDim_nod3d+eDim_nod3D)) 
  do n=1, myDim_nod3d+eDim_nod3D                    
     temp_x(n)=geolon(n)/rad
     temp_y(n)=geolat(n)/rad
     ! change lon range to [0 360]
     if(temp_x(n)<0.) temp_x(n)=temp_x(n) + 360.0  
  end do

 ! read raw data and do interpolation
 if (trim(OceClimaDataName).eq.'annual_woa01_ts.out'.or. trim(OceClimaDataName).eq.'WOA13_TS.txt') then   ! added RT RG4150 !LS
  write(*,*)'read ',trim(OceClimaDataName)
  do i=1, num_lon_reg
     do j=1, num_lat_reg
        read(19, *) raw_data(i,j,1:num_lay_reg)
     end do
  end do
 else
  ! read raw data and do interpolation
  do i=1, num_lay_reg
     do j=1, num_lat_reg
        read(19, *) raw_data(:,j,i)         
     end do
  end do  
 endif


  call interp_3d_field(num_lon_reg, num_lat_reg, num_lay_reg, lon_reg, lat_reg, lay_reg, &
       raw_data, myDim_nod3D+eDim_nod3D, temp_x, temp_y, coord_nod3d(3,:), tracer(:,1))

 ! read raw data and do interpolation
 if (trim(OceClimaDataName).eq.'annual_woa01_ts.out'.or. trim(OceClimaDataName).eq.'WOA13_TS.txt') then   ! added RT RG4150 !LS
  write(*,*)'read ',trim(OceClimaDataName)
  do i=1, num_lon_reg
     do j=1, num_lat_reg
        read(19, *) raw_data(i,j,1:num_lay_reg)
     end do
  end do
 else
  ! read raw data and do interpolation
  do i=1, num_lay_reg
     do j=1, num_lat_reg
        read(19, *) raw_data(:,j,i)         
     end do
  end do  
 endif

  call interp_3d_field(num_lon_reg, num_lat_reg, num_lay_reg, lon_reg, lat_reg, lay_reg, &
       raw_data, myDim_nod3d+eDim_nod3D, temp_x, temp_y, coord_nod3d(3,:), tracer(:,2))

  close(19) 

  ! Convert in situ temperature into potential temperature
  pr=0.0_8
  do i=1,myDim_nod3d+eDim_nod3D    
     tt=tracer(i,1)
     ss=tracer(i,2)
     pp=abs(coord_nod3D(3,i))
     tracer(i,1)=theta(ss, tt, pp, pr)
  end do

  deallocate(temp_y, temp_x, raw_data, lay_reg, lat_reg, lon_reg)
  write(*,*)'read_init_ts completed'
    
end subroutine read_init_ts
!
!-----------------------------------------------------------------------------
!
subroutine read_MY_vara
  ! A better format of MY output/input should be used in the future! 
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !------------------------------------------------------------------

  use o_MESH
  use o_array
  use o_mixing_my2p5_mod
  use g_config
  use g_PARFE
  implicit none

  real(kind=8), allocatable :: aux3(:) 

  allocate(aux3(nod3D))   

  open(35,file=trim(ResultPath)//runid//'_MY_restart.out', status='old')

  read(35,*) aux3
  Kv(:,1)=aux3(myList_nod3d)
  read(35,*) aux3
  Av=aux3(myList_nod3d)
  read(35,*) aux3
  Kq=aux3(myList_nod3d)
  read(35,*) aux3
  q2=aux3(myList_nod3d)
  read(35,*) aux3
  q2b=aux3(myList_nod3d)
  read(35,*) aux3
  q2l=aux3(myList_nod3d)
  read(35,*) aux3
  q2lb=aux3(myList_nod3d)

  close(35)

  deallocate(aux3)
end subroutine Read_MY_vara
