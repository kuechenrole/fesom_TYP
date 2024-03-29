! routines for tracer rhs assembling and equation solving

subroutine ts_sfc_bc
  ! Assemble the tracer surface boundary condition
  ! In both the implicit and explicit vertical mixing schemes cases,
  ! this routine should be called to set up the necessary arrays. 
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------
  
  use o_mesh
  use o_elements
  use o_param
  use o_array
  use g_config
  use g_forcing_param
  use g_forcing_arrays
  use g_clock
  use g_parfe
  implicit none

  integer         :: row, m, elnodes2(3), q, col, elnodes(3)
  real(kind=8)    :: auxf, entries(6), rsss

  if(.not.ts_surfbd) return

  ts_sfc_force=0.0

  ! sss restoring flux
  call cal_relax_salt

  ! virtual salt flux
#ifndef use_fullfreesurf
  rsss=ref_sss
  do row=1,ToDim_nod2d
     m=nod3D_below_nod2D(1,row)	    
     if(ref_sss_local) rsss=tracer(m,2)
     virtual_salt(row)=rsss*water_flux(row) 
  end do
#endif

  ! normalize the salt fluxes: remove the global mean
  if(balance_salt_water) call check_imb_salt_flux


  !apply fluxes and restoring to the RHS
  do row=1,myDim_elem2d             
     elnodes2=elem2D_nodes(:,row)
     elnodes=nod3D_below_nod2D(1,elnodes2)         
     auxf=voltriangle(row)/12.0_8    

#ifndef use_fullfreesurf   

#ifdef use_cavity
     if(all(cavity_flag_nod2d(elnodes2)==0)) then   
#endif   
        entries(1:3)=auxf*(restore_t_surf*(-tracer(elnodes,1)+Tsurf(elnodes2)) &
             - heat_flux(elnodes2)/vcpw)            
        entries(4:6)=auxf*(relax_salt(elnodes2)+virtual_salt(elnodes2))
#ifdef use_cavity
     else
        entries(1:3)=-auxf*heat_flux(elnodes2)/vcpw
        entries(4:6)=auxf*(relax_salt(elnodes2)+virtual_salt(elnodes2)) 
     end if
#endif

#else
     ! then full free surface

#ifdef use_cavity
     if(all(cavity_flag_nod2d(elnodes2)==0)) then   
#endif     
        entries(1:3)=auxf*(restore_t_surf*(-tracer(elnodes,1)+Tsurf(elnodes2)) &
             - heat_flux(elnodes2)/vcpw - tracer(elnodes,1)*water_flux(elnodes2))  !to update
        entries(4:6)=auxf*(relax_salt(elnodes2)+real_salt_flux(elnodes2))
#ifdef use_cavity
     else
        entries(1:3)=-auxf*(heat_flux(elnodes2)/vcpw + tracer(elnodes,1)*water_flux(elnodes2)) !to update
        entries(4:6)=auxf*relax_salt(elnodes2)  !only due to global normalization
     end if
#endif
#endif

     do q=1,3
        col=elnodes2(q) !elnodes2
        ts_sfc_force(col,1)=ts_sfc_force(col,1)+sum(entries(1:3))+entries(q)
        ts_sfc_force(col,2)=ts_sfc_force(col,2)+sum(entries(4:6))+entries(q+3) 
     end do
     if(.not.use_vertdiff_impl) then
        do q=1,3
           col=elnodes(q)                               
           tracer_rhs(col,1)=tracer_rhs(col,1)+sum(entries(1:3))+entries(q)
           tracer_rhs(col,2)=tracer_rhs(col,2)+sum(entries(4:6))+entries(q+3)
        end do
     end if
  end do

end subroutine ts_sfc_bc
!
!============================================================================
!
subroutine cal_relax_salt
  ! prepare restoring surface salt flux
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------

  use o_mesh
  use o_param
  use o_array
  use i_array
  use g_config
  use g_forcing_arrays
  use g_parfe
  implicit none

  integer         :: row, m
  real(kind=8)    :: aux, fac

#ifdef use_ice
  do row=1,ToDim_nod2d
#ifdef use_cavity
     if(cavity_flag_nod2d(row)==1) then  
        relax_salt(row)=0.0
        cycle
     end if
#endif

     fac=1.0
     !if(a_ice(row)>0.05) then
     !   fac=2.0
     !end if

     m=nod3D_below_nod2D(1,row)	
     aux=Ssurf(row)-tracer(m,2)
     !aux=sign(min(abs(aux),0.5), aux) 
     relax_salt(row)=restore_s_surf*aux*fac

     if(tracer(m,2)<salinity_min .and. limit_salinity) then  !force ocean salinity to be above 5.0
        aux=salinity_min-tracer(m,2)
        relax_salt(row)=aux*coeff_limit_salinity
     end if

  end do
#else
  do row=1,ToDim_nod2d
#ifdef use_cavity
     if(cavity_flag_nod2d(row)==1) then  
        relax_salt(row)=0.0
        cycle
     end if
#endif
     m=nod3D_below_nod2D(1,row)	
     aux=Ssurf(row)-tracer(m,2)
     relax_salt(row)=restore_s_surf*aux
  end do
#endif  

end subroutine cal_relax_salt
!
!============================================================================
!
#ifndef use_tracer_gls
subroutine tracer_rhs_tg
  ! Assemble tracer rhs
  !
  ! Coded by Qiang Wang
  ! Reviewed by ??
  !--------------------------------------------------------
  
  use o_mesh
  use o_elements
  use o_param
  use o_array
  use g_config
  use g_diag
  use g_meanarrays
  use g_forcing_arrays
  use g_PARFE
  implicit none 

  integer                      :: i, j, row, elnodes(4)
  integer                      :: elem, elem2, lay, elem_type
  real(kind=8)                 :: Kh, Kv_el, aux, adv, coe, fc
  real(kind=8)                 :: inv2, inv4, inv5, inv20
  real(kind=8)                 :: dx(4), dy(4), dz(4), vol
  real(kind=8)                 :: uvel(4), vvel(4), u2d, v2d
  real(kind=8)                 :: usum, vsum, um, vm, wm
  real(kind=8)                 :: tr_elem(4,num_tracer), entries(4)
  real(kind=8)                 :: aux1, aux2, dif(4)
  real(kind=8)                 :: rotate_coe, temp_coe, temp_coe2
  real(kind=8)                 :: swr_conv
  !
  !variables used for Redi/GM scheme
  real(kind=8)                 :: K_GM, Kh_diag, Kh_other
  real(kind=8)	               :: S(3), fcn1, fcn2, lambd, Z_mean, depth_scale
  real(kind=8)                 :: S_d, c_speed, turb_layer
  data S_d, c_speed /1.0e-3, 2.0/
  !
  real(kind=8)                 :: dparam, beta, gamma
#ifndef use_non_hydrostatic
  integer                      :: elnodes2(3) 
  real(kind=8)                 :: vc(3)
#else
  integer                      :: elnodes23(4)
  real(kind=8)                 :: vc(4), wsum, wvel(4), w2d
#endif
  !
#ifdef use_fullfreesurf
  integer                      :: n_el
  real(kind=8)                 :: coe_diff, wmove(4), wmove_sum
  logical                      :: flag_move=.false.
#endif

  inv2=0.5_8
  inv4=0.25_8
  inv5=0.2_8
  inv20=0.05_8

  do j=1,num_tracer
     do row=1, myDim_nod3d          
        tracer_rhs(row,j)=0.
     enddo
  enddo

  ! assembling tracer rhs
  do elem=1,myDim_elem3d              
     elnodes=elem3D_nodes(:,elem)
     elem2=elem2D_corresp_to_elem3D(elem)
     elem_type=grid_type_elem2d(elem2)
#ifndef use_non_hydrostatic
     elnodes2=elem2d_nodes(:,elem2)
#else
     elnodes23=nod2d_corresp_to_nod3d(elnodes)
#endif
     fc=coriolis_param_elem2d(elem2)

     !diffusivity
     Kh=Kh0
     if(scale_mixing_h) then
        Kh=Kh*(voltriangle(elem2)/scalevol)**(1.0/real(scale_mixing_type_s))
     end if
     if(use_vertdiff_impl) then
        Kv_el=0.0
     else
        Kv_el=sum(Kv(elnodes,1))/4.0 
     end if

     !-------------------------------------------------------------------------------
     if (Redi_GM .and. elem_type==0) then 

        !GM diffusivity
        K_GM  = Kh*ratio_K_GM   

        !neutral slope
        if(nslope_version==1) then
           lay=elem3d_layer(elem)
           S = neutral_slope(:,lay,elem2)   ! S(1:3): Sx,Sy and |S|
        else
           S = neutral_slope_elem(:,elem)
        end if
        !prepare for tapering
        !define 2 functions fcn1 and fcn2, which are required for tapering
        fcn1=1.0_8
        fcn2=1.0_8

        ! fcn1, hyperbolic tangent, used for steep slope region
        if(ODM95) fcn1 = 0.5_8*(1.0_8 + tanh((Slope_critical - S(3))/S_d))

        !we need to check if the element is near the surface in the transit layer
        !If yes, then we need the tapering function fcn2, a sine function of depth.
        if(LDD97) then
           !the first baroclinic Rossby radius
           lambd = c_speed/abs(fc)

           !limit lambda [following Large et al(1997)] to handle singularity
           !at the equator
           if (lambd < 15000.) lambd = 15000.
           if (lambd > 100000.) lambd = 100000.

           !critical depth, above which sine tapering is necessary.
           depth_scale = lambd*S(3)

           !the mean depth of this element
           Z_mean = abs(sum(coord_nod3D(3,elnodes)))/4.0

           turb_layer=100.0
           !here 100.0m depth is assumed to be turbulent and does not need Redi/GM
           !a well defined turbulent layer should be updated later

           !if in the turbulent layer or transit layer, calculate fcn2
           if(Z_mean<turb_layer) then   !turbulent layer
              fcn2=0.0
           elseif(Z_mean < turb_layer+depth_scale)  then   !transit layer
              fcn2 = 0.5*(1.0 + sin(pi*(Z_mean-turb_layer)/depth_scale - pi/2.0))
           end if
        end if

        ! apply tapering
        ! For steep slope region:
        ! a) no taper applied to diagonal piece of horizontal neutral operator
        ! b) hyperbolic tangent(exponential) taper applied to off-diagonal piece of
        !    horizontal operator and to diagonal and off-diagonal piece of vertical
        !    neutral diffusion operator. a)+b) means we transfer the tracer diffusion
        !    to a horizontal-vertical manner in regions of steep neutral slopes.
        ! c) Exponential taper applied to GM operator.
        ! For surface layer with small slope:
        ! a) sine taper applied to both neutral operator and GM operator, except the
        !    diagonal piece of the horizontal diffusion.
        ! In one word, here we use ldd97, but always keep the diagonal part of the 
        ! horizontal diffusion following the suggestion of Griffies (2004).

        ! diffusion part:
        Kh_diag = Kh
        Kh_other = Kh*fcn1*fcn2
        ! skewion part:
        K_GM = K_GM*fcn1*fcn2

	if(any(mod(index_nod3d(elnodes),10)==1)) K_GM=0.0 !b.c.

     end if  	!Redi_GM:  tapered neutral diffusivity computed
     !------------------------------------------------------------------------------

     !derivatives
     dx=bafux_3d(:, elem)
     dy=bafuy_3d(:, elem)
     dz=bafuz_3d(:, elem)
     vol=voltetra(elem)
     !velocity
     uvel=uf0(elnodes)         !u*
     vvel=uf0(elnodes+myDim_nod3d+eDim_nod3D)   !v*    
     usum=sum(uvel)
     vsum=sum(vvel)
#ifndef use_non_hydrostatic
#ifdef use_semiimplicit_scheme
     vc=theta_ssh*ssh(elnodes2)-(gamma_stab-1.0+theta_ssh)*ssh0(elnodes2)
#else
     vc=ssh(elnodes2)-gamma_stab*ssh0(elnodes2)
#endif
     aux1=sum(vc*bafux_2d(:,elem2))*g
     aux2=sum(vc*bafuy_2d(:,elem2))*g
     if(use_cori_semi) then
        dparam=dt_inv**2 + alpha_trapez**2*fc**2
        beta=dt_inv/dparam
        gamma=fc*alpha_trapez/dparam
        u2d=beta*aux1+gamma*aux2
        v2d=beta*aux2-gamma*aux1
     else
        u2d=aux1*dt
        v2d=aux2*dt	
     endif
     um=inv4*usum-u2d
     vm=inv4*vsum-v2d	
     wm=sum(dz*w(elnodes))
#else
     !non_hydrostatic case
     wvel=uf0(elnodes+2*(myDim_nod3d+eDim_nod3D))  
     wsum=sum(wvel)
     vc=g*ssh(elnodes23)+nhp(elnodes) - &
          gamma_stab*g*ssh0(elnodes23)-gamma_stab_nh*nhp0(elnodes)
     aux1=sum(vc*dx)
     aux2=sum(vc*dy)
     if(use_cori_semi) then
        dparam=dt_inv**2 + alpha_trapez**2*fc**2
        beta=dt_inv/dparam
        gamma=fc*alpha_trapez/dparam
        u2d=beta*aux1+gamma*aux2
        v2d=beta*aux2-gamma*aux1
     else
        u2d=aux1*dt
        v2d=aux2*dt	
     endif
     w2d=sum(vc*dz)*dt
     um=inv4*usum-u2d
     vm=inv4*vsum-v2d
     wm=inv4*wsum-w2d
#endif

     !element nodal tracer fields
     tr_elem=tracer(elnodes,:)
     ! shortwave penetration
#ifdef use_sw_pene
     swr_conv=sum(dz*sw_3d(elnodes))*vol
#endif

     ! used for free surface case
#ifdef use_fullfreesurf
     coe=inv20*vol*dt_inv
     n_el=map_elem(elem)
     flag_move=.false.
     if(n_el/=0) then
        flag_move=.true.
        coe_diff=coe-inv20*voltetra_new(n_el)*dt_inv
        wmove=0.
        do i=1, 4
           if(index_nod3d(elnodes(i))>12) cycle
           row=nod2D_corresp_to_nod3D(elnodes(i))     
           wmove(i)=-(ssh(row)-ssh0(row))*dt_inv
        end do
        wmove_sum=sum(wmove)
     end if
#endif
     !for along sigma mixing
     if (elem_type==1) then
        lay=elem3d_layer(elem)     
        S(1)=grid_slope(1,lay,elem2)
        S(2)=grid_slope(2,lay,elem2)
        aux1=S(1)**2+S(2)**2
        S(3)=sqrt(aux1)
        rotate_coe=1.0/(1.0+aux1) 
     end if


     !assembling over nodes
     do i=1,4 
        row=elnodes(i)
        entries=0.0

        ! part of mass matrix due to mesh movement
#ifdef use_fullfreesurf
        if(flag_move) then
           do j=1,num_tracer
              tracer_rhs(row,j)=tracer_rhs(row,j)+(sum(tr_elem(:,j))+tr_elem(i,j))*coe_diff          
           end do
        end if
#endif

        !diffusion
        if(elem_type==1) then  !along-sigma diffusion 
	   !app.: vertical diffusion is kept in the vertical 
           !diagonal part1 (lateral)
	   temp_coe=Kh*rotate_coe
           entries=entries-(temp_coe*dx(i)*(1.0+S(2)*s(2))*dx + &
                temp_coe*dy(i)*(1.0+S(1)*S(1))*dy)
           !diagonal part2 (cross slope)
	   temp_coe2=Kv_el+S(3)*S(3)*temp_coe
           entries=entries-temp_coe2*dz(i)*dz
           !off diagonal part1 (lateral) --> (1,3),(2,3)
           entries=entries-temp_coe*(S(1)*dx(i)+S(2)*dy(i))*dz
           !off diagonal part1 (lateral)--> (1,2),(2,1), '- -' -> '+'
	   temp_coe2=S(1)*S(2)*temp_coe
           entries=entries+(temp_coe2*dx(i)*dy + temp_coe2*dy(i)*dx)
           !off diagonal part2 (cross slope) --> (3,1),(3,2)
           entries=entries-dz(i)*temp_coe*(S(1)*dx+S(2)*dy)
        else
	   if(Redi_GM) then  ! Redi diffusion + GM
       !app: small slope
       !diagonal part1 (lateral)
              entries=entries - Kh_diag*dx(i)*dx - Kh_diag*dy(i)*dy
              !diagonal part2 (cross neutral)
	      aux=(Kv_el+Kh_other*S(3)*S(3))*dz(i)
              entries=entries-aux*dz
              !off diagonal part1 (lateral) 
              aux=(Kh_other-K_GM)*(S(1)*dx(i)+S(2)*dy(i))
              entries=entries-aux*dz
              !off diagonal part2 (cross neutral)
              aux=(Kh_other+K_GM)*dz(i)
              entries=entries-(aux*S(1)*dx+aux*S(2)*dy)
	   else  !horizontal diffusion
              entries=entries - Kh*dx(i)*dx - Kh*dy(i)*dy - Kv_el*dz(i)*dz
	   end if
        end if

        !advection
#ifndef use_non_hydrostatic
#ifndef use_fullfreesurf
        entries=entries - ((usum+uvel(i))*inv5-u2d)*inv4*dx - &
             ((vsum+vvel(i))*inv5-v2d)*inv4*dy - wm*inv4*dz
#else
        entries=entries+(dx(i)*(usum+uvel)+dy(i)*(vsum+vvel))*inv20
        entries=entries+dz(i)*wm*inv4
        entries=entries-(dx(i)*u2d+dy(i)*v2d)*inv4
        if(flag_move) entries=entries+dz(i)*(wmove_sum+wmove)*inv20
#endif
#else
#ifndef use_fullfreesurf
        entries=entries - ((usum+uvel(i))*inv5-u2d)*inv4*dx - &
             ((vsum+vvel(i))*inv5-v2d)*inv4*dy - &
             ((wsum+wvel(i))*inv5-w2d)*inv4*dz
#else
        entries=entries+(dx(i)*(usum+uvel)+dy(i)*(vsum+vvel) + &
             dz(i)*(wsum+wvel))*inv20
        entries=entries-(dx(i)*u2d+dy(i)*v2d+dz(i)*w2d)*inv4
        if(flag_move) entries=entries+dz(i)*(wmove_sum+wmove)*inv20
#endif
#endif

        !TG stabilization
        aux=(um*dx(i)+vm*dy(i)+wm*dz(i))*dt*inv2   
#ifdef use_fullfreesurf
        if(flag_move) aux=aux+wmove_sum*inv4*dz(i)*dt*inv2 
#endif
        entries=entries-aux*(um*dx+vm*dy+wm*dz)
#ifdef use_fullfreesurf
        if(flag_move) then
           entries=entries-aux*wmove_sum*inv4*dz
        end if
#endif     

        !sum up
        do j=1,num_tracer
           tracer_rhs(row,j)=tracer_rhs(row,j)+sum(entries*tr_elem(:,j))*vol
        end do

        ! in case of considering shortwave penetration into the ocean
#ifdef use_sw_pene
        tracer_rhs(row,1)=tracer_rhs(row,1)+swr_conv*inv4 
#endif

        ! local or near open boundary restoring
        if(buffer_zone) then
           aux=tracer_restore_coeff(row)*vol*inv20
           do j=1,num_tracer  !!!
              dif=tracer0(elnodes,j)-tr_elem(:,j)
              tracer_rhs(row,j)=tracer_rhs(row,j)+aux*(sum(dif)+dif(i))
           end do
        end if

     end do  ! i node

     ! Add elementwise SGS velocity and fluxes to temporary arrays for diagnostics
     ! currently only fluxes of T/S are saved. Modify the code to save more tracers
#ifdef allow_diag
     if(diag_oce) then
        if(elem_type==1) then ! sigma grid
           if(diag_oce_SGS_transp) then
              aux1=sum(dx*tr_elem(:,1))
              aux2=sum(dy*tr_elem(:,1))
              aux=sum(dz*tr_elem(:,1))
              sgs_ut(elem)=sgs_ut(elem)-temp_coe*aux1*(1.0+S(2)*S(2)) &
                   -temp_coe*S(1)*aux+temp_coe2*aux2
              sgs_vt(elem)=sgs_vt(elem)-temp_coe*aux2*(1.0+S(1)*S(1)) &
                   -temp_coe*S(2)*aux+temp_coe2*aux1
              aux1=sum(dx*tr_elem(:,2))
              aux2=sum(dy*tr_elem(:,2))
              aux=sum(dz*tr_elem(:,2))
              sgs_us(elem)=sgs_us(elem)-temp_coe*aux1*(1.0+S(2)*S(2)) &
                   -temp_coe*S(1)*aux+temp_coe2*aux2
              sgs_vs(elem)=sgs_vs(elem)-temp_coe*aux2*(1.0+S(1)*S(1)) &
                   -temp_coe*S(2)*aux+temp_coe2*aux1
           endif
        else
           if(Redi_GM) then
              if(diag_oce_GM_vel) then
                 ! GM velocity
                 sgs_u(elem)=sgs_u(elem)-K_GM*S(1)   
                 sgs_v(elem)=sgs_v(elem)-K_GM*S(2)  
              end if
              ! flux
              if(diag_oce_SGS_transp) then
                 aux=sum(dz*tr_elem(:,1))
                 sgs_ut(elem)=sgs_ut(elem)-Kh_diag*sum(dx*tr_elem(:,1))-(Kh_other-K_GM)*S(1)*aux
                 sgs_vt(elem)=sgs_vt(elem)-Kh_diag*sum(dy*tr_elem(:,1))-(Kh_other-K_GM)*S(2)*aux
                 aux=sum(dz*tr_elem(:,2))
                 sgs_us(elem)=sgs_us(elem)-Kh_diag*sum(dx*tr_elem(:,2))-(Kh_other-K_GM)*S(1)*aux
                 sgs_vs(elem)=sgs_vs(elem)-Kh_diag*sum(dy*tr_elem(:,2))-(Kh_other-K_GM)*S(2)*aux
              end if
           else
              if(diag_oce_SGS_transp) then
                 sgs_ut(elem)=sgs_ut(elem)-Kh*sum(dx*tr_elem(:,1))
                 sgs_vt(elem)=sgs_vt(elem)-Kh*sum(dy*tr_elem(:,1))
                 sgs_us(elem)=sgs_us(elem)-Kh*sum(dx*tr_elem(:,2))
                 sgs_vs(elem)=sgs_vs(elem)-Kh*sum(dy*tr_elem(:,2))
              end if
           end if
        end if
     end if
#endif

  end do  ! element

end subroutine tracer_rhs_tg
#endif
!
!----------------------------------------------------------------------------
!
subroutine impl_vertdiff
  ! Apply implicit vertical diffusivity; lumped mass matrix is used.
  ! 
  ! Coded by Qiang Wang and Sergey Danilov
  ! Reviewed by ??
  !--------------------------------------------------------
  
  use o_param
  use o_array
  use o_mesh
  use o_elements
  use o_mixing_kpp_mod
  use o_passive_tracer_mod
  use g_config
  use g_parfe
  implicit none

  integer            :: n2, nlay, k, i, j, q, p, cnt
  integer            :: row, elem, elnodes(4), n_el
  integer            :: nodup, nodlo
  real(kind=8)       :: vol, vol_visc, inv4, Kv_el, Kv_el2
  real(kind=8)       :: rhs_nonloc(2)
  real(kind=8)       :: a(max_num_layers,2), b(max_num_layers,2), c(max_num_layers,2)
  real(kind=8)       :: trr(num_tracer, max_num_layers), tr_nod(num_tracer)

  inv4=0.25_8

  do n2=1,myDim_nod2d           
     nlay=num_layers_below_nod2d(n2)+1

     ! assemble three diagonal matrix and rhs
     trr=0.
     do k=1,nlay
        a(k,:)=0.
        b(k,:)=0.
        c(k,:)=0.

        row=nod3d_below_nod2d(k,n2)
        tr_nod=tracer(row,:)

	nodup=0
	nodlo=0
        if(k>1) nodup=nod3d_below_nod2d(k-1,n2)
        if(k<nlay) nodlo=nod3d_below_nod2d(k+1,n2)
        do i=1,nod_in_elem3D(row)%nmb
           elem=nod_in_elem3D(row)%addresses(i)
           elnodes=elem3D_nodes(:,elem)
           vol_visc=voltetra(elem)
#ifdef use_fullfreesurf
           n_el=map_elem(elem)
           if(n_el==0) then
              vol=voltetra(elem)
           else
              vol=voltetra_new(n_el)
           end if
#else
           vol=voltetra(elem)
#endif

           do q=1,4
              if(elnodes(q)==row) then
                 p=q
                 exit
              end if
           end do

           cnt=0
           rhs_nonloc=0.0

           !first entry
           if(k>1) then
              do q=1,4
                 if(elnodes(q)==nodup) then
                    Kv_el=Kv(nodup,1)  !Kv(nodup) is the Kv for this segment
                    if(trim(mix_scheme)=='MY2p5') then
                       Kv_el=Kv_el+Kv0
                    end if
                    a(k,1)=a(k,1) + bafuz_3d(p,elem) * bafuz_3d(q,elem) * Kv_el * vol_visc
                    !second entry
                    b(k,1)=b(k,1) + bafuz_3d(p,elem) * bafuz_3d(p,elem) * Kv_el * vol_visc
                    if(trim(mix_scheme)=='KPP') then
                       if(double_diffusion) then
                          Kv_el2=Kv(nodup,2)
                          a(k,2)=a(k,2) + bafuz_3d(p,elem) * bafuz_3d(q,elem) * Kv_el2 * vol_visc
                          !second entry
                          b(k,2)=b(k,2) + bafuz_3d(p,elem) * bafuz_3d(p,elem) * Kv_el2 * vol_visc
                       else
                          Kv_el2=Kv_el
                       end if
                       ! nonlocal transport to the rhs (only T and S currently)
                       rhs_nonloc(1)=bafuz_3d(p,elem)*vol_visc*min(blmc(nodup,2)*ghats(nodup),1.)*heat_flux(n2)/vcpw
                       rhs_nonloc(2)=-bafuz_3d(p,elem)*vol_visc*min(blmc(nodup,3)*ghats(nodup),1.)*tracer(n2,2)*water_flux(n2)
                    end if

                    cnt=1
                    exit
                 end if
              end do
           end if

           !third entry
           if(k<nlay) then
              do q=1,4
                 if(elnodes(q)==nodlo) then
                    Kv_el=Kv(row,1)    !Kv(row) is the Kv for this segment
                    if(trim(mix_scheme)=='MY2p5') then
                       Kv_el=Kv_el+Kv0
                    end if
                    c(k,1)=c(k,1) + bafuz_3d(p,elem) * bafuz_3d(q,elem) * Kv_el * vol_visc
                    !second entry
                    b(k,1)=b(k,1) + bafuz_3d(p,elem) * bafuz_3d(p,elem) * Kv_el * vol_visc
                    if(trim(mix_scheme)=='KPP') then
                       if(double_diffusion) then
                          Kv_el2=Kv(row,2)
                          c(k,2)=c(k,2) + bafuz_3d(p,elem) * bafuz_3d(q,elem) * Kv_el2 * vol_visc
                          !second entry
                          b(k,2)=b(k,2) + bafuz_3d(p,elem) * bafuz_3d(p,elem) * Kv_el2 * vol_visc
                       else
                          Kv_el2=Kv_el
                       end if
                       ! nonlocal transport to the rhs (only T and S currently)
                       rhs_nonloc(1)=bafuz_3d(p,elem)*vol_visc*min(blmc(row,2)*ghats(row),1.)*heat_flux(n2)/vcpw
                       rhs_nonloc(2)=-bafuz_3d(p,elem)*vol_visc*min(blmc(row,3)*ghats(row),1.)*tracer(n2,2)*water_flux(n2)
                    end if

                    cnt=1
                    exit
                 end if
              end do
           end if

           !second entry, mass matrix part
           b(k,:)=b(k,:) + vol*inv4*dt_inv

           !rhs
           do j=1,num_tracer
              trr(j,k)=trr(j,k)+tr_nod(j)*vol*inv4*dt_inv
           end do
           !add non-local term
           trr(1,k)=trr(1,k)+rhs_nonloc(1)
           trr(2,k)=trr(2,k)+rhs_nonloc(2)          

        end do  !i
     end do  !k

     !add surface forcing to rhs
     trr(1:2,1)=trr(1:2,1)+ts_sfc_force(n2,1:2)  !T&S
     if(use_passive_tracer .and. passive_tracer_flux) then
        do j=1, num_passive_tracer
           trr(index_passive_tracer(j),1)=trr(index_passive_tracer(j),1) + ptr_sfc_force(n2,j)
        end do
     end if

     ! the sweep algorithm
     if(trim(mix_scheme)=='KPP' .and. double_diffusion) then
        ! forward step
        ! prepare coefficients 
        c(1,:)=-c(1,:)/b(1,:)
        trr(1,1)=trr(1,1)/b(1,1)
        trr(2:,1)=trr(2:,1)/b(1,2)
        do k=2,nlay
           b(k,:)=1.0/(a(k,:)*c(k-1,:)+b(k,:))
           c(k,:)=-c(k,:)*b(k,:)
           trr(1,k)=(trr(1,k)-a(k,1)*trr(1,k-1))*b(k,1)
           trr(2:,k)=(trr(2:,k)-a(k,2)*trr(2:,k-1))*b(k,2)
        end do
        ! backward sweep
        do k=nlay-1,1,-1
           trr(1,k)=trr(1,k)+c(k,1)*trr(1,k+1)
           trr(2:,k)=trr(2:,k)+c(k,2)*trr(2:,k+1)
        end do
     else
        ! forward step
        ! prepare coefficients 
        c(1,1)=-c(1,1)/b(1,1)
        trr(:,1)=trr(:,1)/b(1,1)
        do k=2,nlay
           b(k,1)=1.0/(a(k,1)*c(k-1,1)+b(k,1))
           c(k,1)=-c(k,1)*b(k,1)
           trr(:,k)=(trr(:,k)-a(k,1)*trr(:,k-1))*b(k,1)
        end do
        ! backward sweep
        do k=nlay-1,1,-1
           trr(:,k)=trr(:,k)+c(k,1)*trr(:,k+1)
        end do
     end if

     ! update tracers
     do k=1,nlay
        row=nod3d_below_nod2d(k,n2)
        tracer(row,:)=trr(:,k)
     end do

  end do  !2d nodes

  do j=1,num_tracer
     call com_3D(tracer(:,j))
  end do

end subroutine impl_vertdiff
!
!----------------------------------------------------------------------------
!
subroutine tracer_solve
  ! Tricky solver for ocean tracers
  ! Getting better efficiency by loosing accuracy!
  ! Better solution method in the future required.
  !
  ! Coded by Qiang Wang
  ! Reviewed by Sergey Danilov
  !--------------------------------------------------------

  use o_matrices
  use o_mesh
  use o_elements
  use o_param
  use o_array
  use g_config
  use g_parfe
  implicit none
  !
  integer                                 :: n, clo, clo2, cn, location(100), row, j
  real(kind=8)                            :: rhs_new
  real(kind=8), allocatable               :: auxarray(:,:)

  allocate(auxarray(myDim_nod3d,num_tracer))

  !the first approximation
  do j=1,num_tracer
     do row=1,myDim_nod3d              
        dtracer(row,j)=tracer_rhs(row,j)/ts_lump(row)
     end do
     call com_3D(dtracer(:,j))
  end do

  !iterate 
  do n=1,num_iter_solve-1                  
     do row=1,myDim_nod3d           
        clo=tsstiff%rowptr(row)-tsstiff%rowptr(1)+1  
        clo2=tsstiff%rowptr(row+1)-tsstiff%rowptr(1)  
        cn=clo2-clo+1
        location(1:cn)=nghbr_nod3D(row)%addresses    
        do j=1,num_tracer
           rhs_new=tracer_rhs(row,j) - sum(tsstiff%values(clo:clo2)*dtracer(location(1:cn),j))
           auxarray(row,j)=dtracer(row,j)+rhs_new/ts_lump(row)  
        end do
     end do

     do j=1,num_tracer 
        do row=1,myDim_nod3d            
           dtracer(row,j)=auxarray(row,j)  
        end do
        call com_3D(dtracer(:,j))
     end do
  end do

  deallocate(auxarray)
end subroutine tracer_solve
!
!----------------------------------------------------------------------------
!
subroutine compute_neutral_slope
  ! calculate neutral slopes 
  !
  ! OUTPUT:
  ! version 1: neutral_slope(3,layer,elem2d), over prism
  ! version 2: neutral_slope_elem(3, elem3d), elementwise neutral slope   
  ! 
  ! REFERENCE:
  !    McDougall, T.J. and  D.R. Jackett, 1988  
  !    On the helical nature of neutral surfaces
  !    Progress in Oceanography, vol 20, Pergamon, 153-183
  !    (about the definition of normal direction of neutral surface)
  !
  !    Griffies, S.M. et al. 1998
  !    Isoneutral Diffusion in a z-coordinate ocean model
  !    JPO, vol 28, 805-830
  !
  ! Coded by Qiang Wang, 25,11,2004
  ! Modified by Qiang Wang, 02,07,2010, add option of prismatic slope
  ! Reviewed by ??
  !-------------------------------------------------------------------
  
  use o_mesh
  use o_elements
  use o_param
  use o_array
  use g_config
  use g_parfe
  implicit none

  integer :: i, k, nod, elem, lay_m, elnodes2(3), elnodes(6), lay_el(3)
  integer :: elnodes_tetra(4)
  real    :: rho(6), zm, dz, dx2d(3), dy2d(3), denom, ano_1, ano_2
  real    :: rhograd_x(max_num_layers), rhograd_y(max_num_layers), rhograd_z(max_num_layers)
  real    :: t, s, p, sw_alpha, sw_beta, g_t_x, g_t_y, g_t_z, g_s_x, g_s_y, g_s_z
  real    :: inv2, inv3, inv4, inv6

  inv2=0.5
  inv3=1.0/3.0
  inv4=0.25
  inv6=1.0/6.0

  if(nslope_version==1) then
     do elem=1, myDim_elem2D                  
        if(grid_type_elem2d(elem)==1) cycle  !only apply GM to z-level grids
        elnodes2=elem2d_nodes(:,elem)
        dx2d=bafux_2d(:,elem)
        dy2d=bafuy_2d(:,elem)
        lay_el=num_layers_below_nod2d(elnodes2)
        lay_m=minval(lay_el)

        do k=1,lay_m
           elnodes(1:3)=nod3d_below_nod2d(k,elnodes2)
           elnodes(4:6)=nod3d_below_nod2d(k+1,elnodes2)
           zm=sum(coord_nod3d(3,elnodes))*inv6
           dz=1.0/(coord_nod3d(3,elnodes(1))-coord_nod3d(3,elnodes(4)))
           do i=1,6
              nod=elnodes(i)
              call fcn_density(tracer(nod,1),tracer(nod,2),zm,rho(i))
           end do
           rhograd_x(k)=(sum(dx2d*rho(1:3))+sum(dx2d*rho(4:6)))*inv2
           rhograd_y(k)=(sum(dy2d*rho(1:3))+sum(dy2d*rho(4:6)))*inv2
           rhograd_z(k)=(sum(rho(1:3))-sum(rho(4:6)))*inv3*dz
        end do

        do k=1,lay_m
           if(lay_m>1) then
              if(k==1) then
                 denom=(2.0*rhograd_z(1)+rhograd_z(2))*inv3
              elseif(k<lay_m) then
                 denom=(rhograd_z(k-1)+2.0*rhograd_z(k)+rhograd_z(k+1))*inv4
              else
                 denom=(2.0*rhograd_z(lay_m)+rhograd_z(lay_m-1))*inv3
              end if
           else
              denom=rhograd_z(1)
           end if
           if(denom<0.0) then
              denom=denom-1.0e-20
              neutral_slope(1,k,elem)=-rhograd_x(k)/denom
              neutral_slope(2,k,elem)=-rhograd_y(k)/denom
              neutral_slope(3,k,elem) = sqrt(neutral_slope(1,k,elem)**2 + neutral_slope(2,k,elem)**2)
           else
              neutral_slope(:,k,elem)=0.0
           end if

        end do
     end do

  else !version 2

     uv_rhs(1:ToDim_nod3d)=0.   ! to save memory we use uv_rhs as a temporary array

     do elem = 1, myDim_elem3d
        elnodes_tetra=elem3D_nodes(:,elem)

        ! alpha and beta
        t=inv4*sum(tracer(elnodes_tetra,1))
        s=inv4*sum(tracer(elnodes_tetra,2))
        p=abs(inv4*sum(coord_nod3D(3,elnodes_tetra))) 
        call sw_alpha_beta(t,s,p,sw_alpha,sw_beta)

        g_t_z = sum(bafuz_3d(:,elem)*tracer(elnodes_tetra,1))
        g_s_z = sum(bafuz_3d(:,elem)*tracer(elnodes_tetra,2))
        denom = -sw_alpha*g_t_z + sw_beta*g_s_z

        if(denom>=0.0) then
           uv_rhs(elnodes_tetra)=1.
           neutral_slope_elem(:,elem)=0.0
           cycle
        end if

        denom=denom-1.e-20

        g_t_x = sum(bafux_3d(:,elem)*tracer(elnodes_tetra,1))
        g_s_x = sum(bafux_3d(:,elem)*tracer(elnodes_tetra,2))
        g_t_y = sum(bafuy_3d(:,elem)*tracer(elnodes_tetra,1))
        g_s_y = sum(bafuy_3d(:,elem)*tracer(elnodes_tetra,2))  

        ano_1 = -sw_alpha*g_t_x + sw_beta*g_s_x
        ano_2 = -sw_alpha*g_t_y + sw_beta*g_s_y

        neutral_slope_elem(1,elem) = -ano_1/denom
        neutral_slope_elem(2,elem) = -ano_2/denom
        neutral_slope_elem(3,elem) = &
             sqrt(neutral_slope_elem(1,elem)**2 + neutral_slope_elem(2,elem)**2)
     end do

     ! in case of static instability
     do i=1,myDim_nod3D
        if(uv_rhs(i)>0.5) then
           neutral_slope_elem(:,nod_in_elem3d(i)%addresses)=0.0
        end if
     end do

  end if
end subroutine compute_neutral_slope
!
!----------------------------------------------------------------------------
!
subroutine sw_alpha_beta(t1, s1, p1, alpha, beta)
  !   A function to calculate the thermal expansion coefficient
  !   and saline contraction coefficient.
  !
  ! INPUT: t1 (c), s1 (psu), p1 (db)
  !
  ! OUTPUT:
  !    alpha = Thermal expansion coeff (alpha) [degree_C.^-1]
  !    beta  = Saline contraction coeff (beta) [psu.^-1]
  !
  ! REFERENCE:
  !    McDougall, T.J. 1987.  Neutral Surfaces
  !    Journal of Physical Oceanography, vol 17, 1950-1964,
  !
  ! CHECK VALUE:
  !    sw_beta=0.72088e-3 psu^-1 @ S=40.0psu, ptmp=10.0C (ITS-90), p=4000db
  !    a_over_b=0.34765 psu*C^-1 @ S=40.0psu, ptmp=10.0C, p=4000db
  !
  ! Coded by Qiang Wang, 25,11,2004
  ! Reviewed by ??
  !-----------------------------------------------------------------

  implicit none

  real :: t1, s1, p1, alpha, beta
  real :: t1_2,t1_3,t1_4,p1_2,p1_3,s35,s35_2 
  real :: a_over_b    

  t1_2 = t1*t1
  t1_3 = t1_2*t1
  t1_4 = t1_3*t1
  p1_2 = p1*p1
  p1_3 = p1_2*p1
  s35 = s1-35.0_8
  s35_2 = s35*s35

  ! calculate beta
  beta = 0.785567e-3 - 0.301985e-5*t1 &
       + 0.555579e-7*t1_2 - 0.415613e-9*t1_3 &
       + s35*(-0.356603e-6 + 0.788212e-8*t1 &
       + 0.408195e-10*p1 - 0.602281e-15*p1_2) &
       + s35_2*(0.515032e-8) & 
       + p1*(-0.121555e-7 + 0.192867e-9*t1 - 0.213127e-11*t1_2) &
       + p1_2*(0.176621e-12 - 0.175379e-14*t1) &
       + p1_3*(0.121551e-17)

  ! calaculate the thermal expansion / saline contraction ratio
  a_over_b = 0.665157e-1 + 0.170907e-1*t1 &
       - 0.203814e-3*t1_2 + 0.298357e-5*t1_3 &
       - 0.255019e-7*t1_4 &
       + s35*(0.378110e-2 - 0.846960e-4*t1 &
       - 0.164759e-6*p1 - 0.251520e-11*p1_2) &
       + s35_2*(-0.678662e-5) &
       + p1*(0.380374e-4 - 0.933746e-6*t1 + 0.791325e-8*t1_2) &
       + p1_2*t1_2*(0.512857e-12) &
       - p1_3*(0.302285e-13)

  ! calculate alpha
  alpha = a_over_b*beta

end subroutine sw_alpha_beta
!
