module mod_flux_array
  use, intrinsic :: iso_fortran_env, only: ik => int32, rk => real64
  use, intrinsic :: ieee_arithmetic
  use mod_vector, only: vector_t
  use mod_eos, only: eos

  implicit none

  private
  public :: get_fluxes

contains

  subroutine get_fluxes(rho, u, v, p, H, lbounds)
    !< Implementation of the flux tensor (H) construction. This requires the primitive variables
    integer(ik), dimension(2), intent(in) :: lbounds
    real(rk), dimension(lbounds(1):, lbounds(2):), intent(in) :: rho !< (i,j)
    real(rk), dimension(lbounds(1):, lbounds(2):), intent(in) :: u   !< (i,j)
    real(rk), dimension(lbounds(1):, lbounds(2):), intent(in) :: v   !< (i,j)
    real(rk), dimension(lbounds(1):, lbounds(2):), intent(in) :: p   !< (i,j)
    real(rk), dimension(:, :, :, :), allocatable, intent(out) :: H !< ((Fi, Gj), (1:4), i, j) flux array

    real(rk), dimension(:, :), allocatable :: E !< total energy
    integer(ik) :: i, j
    integer(ik) :: ilo
    integer(ik) :: ihi
    integer(ik) :: jlo
    integer(ik) :: jhi

    ilo = lbound(rho, dim=1)
    ihi = ubound(rho, dim=1)
    jlo = lbound(rho, dim=2)
    jhi = ubound(rho, dim=2)

    ! get the total energy
    allocate(E, mold=rho)
    call eos%total_energy(rho, u, v, p, E)

    ! The flux tensor is H = Fi + Gj

    !$omp parallel default(none), &
    !$omp private(i, j, ilo, ihi, jlo, jhi) &
    !$omp shared(H, rho, u, v, p, E)
    !$omp do simd
    do j = jlo, jhi
      do i = ilo, ihi
        ! F
        H(1, 1, i, j) = rho(i, j) * u(i, j)
        H(2, 1, i, j) = rho(i, j) * u(i, j)**2 + p(i, j)
        H(3, 1, i, j) = rho(i, j) * u(i, j) * v(i, j)
        H(4, 1, i, j) = u(i, j) * (rho(i, j) * E(i, j) + p(i, j))

        ! G
        H(1, 2, i, j) = rho(i, j) * v(i, j)
        H(2, 2, i, j) = rho(i, j) * u(i, j) * v(i, j)
        H(3, 2, i, j) = rho(i, j) * v(i, j)**2 + p(i, j)
        H(4, 2, i, j) = v(i, j) * (rho(i, j) * E(i, j) + p(i, j))
      end do
    end do
    !$omp end do simd
    !$omp end parallel

  end subroutine

  ! pure function flux_dot_vector(lhs, vec) result(output)
  !   !< Implementation of the dot product between a flux tensor and a vector, e.g. H . v
  !   type(flux_tensor_t), intent(in) :: lhs  !< Left-hand side of the dot product
  !   real(rk), dimension(2), intent(in) :: vec  !< Right-hand side of the dot product
  !   real(rk), dimension(4) :: output

  !   ! The flux tensor is H = Fi + Gj
  !   output = lhs%state(:, 1) * vec(1) + lhs%state(:, 2) * vec(2)
  ! end function

end module mod_flux_array
