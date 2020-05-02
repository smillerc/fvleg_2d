module mod_second_order_sgg_structured_reconstruction

  use, intrinsic :: iso_fortran_env, only: ik => int32, rk => real64
  use mod_globals, only: debug_print
  use mod_abstract_reconstruction, only: abstract_reconstruction_t
  use mod_grid, only: grid_t
  use mod_slope_limiter, only: slope_limiter_t
  use mod_input, only: input_t
  use mod_eos, only: eos
  use mod_floating_point_utils, only: equal
  use mod_gradients, only: green_gauss_gradient_limited, get_smoothness

  implicit none

  private
  public :: second_order_sgg_structured_reconstruction_t

  type, extends(abstract_reconstruction_t) :: second_order_sgg_structured_reconstruction_t
    !< Implementation of a 2nd order piecewise-linear reconstruction operator described
    !< in the original FVLEG paper
  contains
    procedure, public :: initialize
    procedure, public :: reconstruct
    ! procedure, public :: reconstruct_point
    procedure, private :: estimate_gradient
    ! procedure, public :: copy
    final :: finalize
  end type

contains

  subroutine initialize(self, input, grid_target)
    !< Construct the second_order_sgg_structured_reconstruction_t type

    class(second_order_sgg_structured_reconstruction_t), intent(inout) :: self
    class(input_t), intent(in) :: input
    class(grid_t), intent(in), target :: grid_target

    integer(ik) :: alloc_status

    call debug_print('Initializing second_order_sgg_structured_reconstruction_t', __FILE__, __LINE__)

    self%order = 2
    self%name = 'piecewise_linear_reconstruction'

    self%grid => grid_target

    call self%set_slope_limiter(name=input%slope_limiter)

  end subroutine initialize

  subroutine finalize(self)
    !< Finalize the second_order_sgg_structured_reconstruction_t type
    type(second_order_sgg_structured_reconstruction_t), intent(inout) :: self
    integer(ik) :: alloc_status

    call debug_print('Running second_order_sgg_structured_reconstruction_t%finalize()', __FILE__, __LINE__)

    if(associated(self%grid)) nullify(self%grid)
    if(associated(self%rho)) nullify(self%rho)
    if(associated(self%u)) nullify(self%u)
    if(associated(self%v)) nullify(self%v)
    if(associated(self%p)) nullify(self%p)
    if(allocated(self%cell_gradient)) deallocate(self%cell_gradient)
  end subroutine finalize

  subroutine copy(out_recon, in_recon)
    class(abstract_reconstruction_t), intent(in) :: in_recon
    class(second_order_sgg_structured_reconstruction_t), intent(inout) :: out_recon

    ! call debug_print('Running second_order_sgg_structured_reconstruction_t%copy()', __FILE__, __LINE__)

    ! if(associated(out_recon%grid)) nullify(out_recon%grid)
    ! out_recon%grid => in_recon%grid

    ! if(associated(out_recon%primitive_vars)) nullify(out_recon%primitive_vars)
    ! out_recon%primitive_vars => in_recon%primitive_vars

    ! if(allocated(out_recon%name)) deallocate(out_recon%name)
    ! allocate(out_recon%name, source=in_recon%name)

    ! if(allocated(out_recon%cell_gradient)) deallocate(out_recon%cell_gradient)
    ! allocate(out_recon%cell_gradient, source=in_recon%cell_gradient)

    ! out_recon%limiter = in_recon%limiter
    ! out_recon%domain_has_been_reconstructed = .false.
  end subroutine

  function reconstruct_point(self, xy, cell_ij) result(V_bar)
    !< Reconstruct the value of the primitive variables (U) at location (x,y)
    !< withing a cell (i,j)

    class(second_order_sgg_structured_reconstruction_t), intent(in) :: self
    real(rk), dimension(2), intent(in) :: xy !< where should V_bar be reconstructed at?
    integer(ik), dimension(2), intent(in) :: cell_ij !< cell (i,j) indices to reconstruct within
    real(rk), dimension(4) :: V_bar  !< V_bar = reconstructed [rho, u, v, p]
    ! real(rk), dimension(2) :: centroid_xy !< (x,y) location of the cell centroid
    integer(ik) :: i, j

    i = cell_ij(1); j = cell_ij(2)
    V_bar = self%interpolate(i=i, j=j, x=xy(1), y=xy(2))

  end function reconstruct_point

  subroutine reconstruct(self, primitive_var, reconstructed_var, lbounds)
    !< Reconstruct a primitive variable [rho, u, v, p]
    !< based on the chosen reconstruction order, e.g. using a piecewise-linear function based on the
    !< selected cell and it's neighbors.

    class(second_order_sgg_structured_reconstruction_t), intent(inout) :: self
    integer(ik), dimension(2), intent(in) :: lbounds
    real(rk), dimension(lbounds(1):, lbounds(2):), intent(out) :: primitive_var !< (i,j); cell primitive variable to reconstruct
    real(rk), dimension(:, lbounds(1):, lbounds(2):), intent(out) :: reconstructed_var
    !< ((corner1:midpoint4), i, j); reconstructed variable, the first index is 1:8, or (c1,m1,c2,m2,c3,m3,c4,m4), c:corner, m:midpoint

    real(rk), dimension(:, :, :), allocatable :: gradient
    integer(ik) :: i, j, p
    integer(ik) :: ilo, ihi, jlo, jhi
    real(rk) :: x_ij, y_ij

    ! Bounds do not include ghost cells. Ghost cells get their
    ! reconstructed values and gradients from the boundary conditions
    ilo = lbound(reconstructed_var, dim=2) + 1
    ihi = ubound(reconstructed_var, dim=2) - 1
    jlo = lbound(reconstructed_var, dim=3) + 1
    jhi = ubound(reconstructed_var, dim=3) - 1

    allocate(gradient(2, ilo:ihi, jlo:jhi))

    ! Find the unlimited gradients sets the self%cell_gradients array
    call self%estimate_gradient(primitive_var, gradient)

    !$omp parallel default(none), &
    !$omp private(i, j, p, ilo, ihi, jlo, jhi, x_ij, y_ij) &
    !$omp shared(reconstructed_var, self, gradient, primitive_var)
    !$omp do simd
    do j = jlo, jhi
      do i = ilo, ihi
        x_ij = self%grid%cell_centroid_x(i, j)
        y_ij = self%grid%cell_centroid_y(i, j)
        do p = 1, 8
          associate(x=>self%grid%cell_node_x(p, i, j), &
                    y=>self%grid%cell_node_y(p, i, j), &
                    d_dx=>gradient(1, i, j), d_dy=>gradient(2, i, j))
            reconstructed_var(p, i, j) = primitive_var(i, j) + d_dx * (x - x_ij) + d_dy * (y - y_ij)
          end associate
        end do
      end do
    end do
    !$omp end do simd
    !$omp end parallel

    self%domain_has_been_reconstructed = .true.
    deallocate(gradient)
  end subroutine reconstruct

  subroutine estimate_gradient(self, primitive_var, gradient)
    !< Estimate the slope-limited gradient of the primitive variables in the cell (i,j). This assumes
    !< a quadrilateral structured grid
    class(second_order_sgg_structured_reconstruction_t), intent(inout) :: self

    real(rk), dimension(:, :), intent(in) :: primitive_var !< (i,j); data to estimate the gradient of
    real(rk), dimension(:, :, :), intent(out) :: gradient !< (i,j); data to estimate the gradient of

    integer(ik) :: i, j, k
    integer(ik) :: ilo, ihi, jlo, jhi

    real(rk), dimension(4) :: edge_lengths  !< length of each face
    real(rk), dimension(4) :: v_edge !< value of the primitive variable at the cell interface, aka edge
    real(rk), dimension(2, 4) :: edge_normals  !< normal vectors of each face
    real(rk) :: d_dx, d_dy
    real(rk) :: phi_left_right, phi_up_down

    ilo = lbound(self%rho, dim=1) + 1
    ihi = ubound(self%rho, dim=1) - 1
    jlo = lbound(self%rho, dim=2) + 1
    jhi = ubound(self%rho, dim=2) - 1

    !$omp parallel default(none), &
    !$omp private(i, j, ilo, ihi, jlo, jhi, phi_left_right, phi_up_down, d_dx, d_dy) &
    !$omp private(edge_normals, v_edge, edge_lengths) &
    !$omp shared(gradient, primitive_var, self)
    !$omp do
    do j = jlo, jhi
      do i = ilo, ihi

        associate(center=>primitive_var(i, j), &      ! current cell
                  bottom=>primitive_var(i, j - 1), &  ! bottom cell
                  right=>primitive_var(i + 1, j), &   ! right cell
                  top=>primitive_var(i, j + 1), &     ! top cell
                  left=>primitive_var(i - 1, j))      ! left cell

          ! if (abs(center - right) < EPS .and. abs(center - left) < EPS) then
          !   d_dx = 0.0_rk
          ! else
          !   ! Edge (face) interface data
          !   edge_lengths(1) = self%grid%cell_edge_lengths(1, i, j - 1)  ! bottom
          !   edge_lengths(2) = self%grid%cell_edge_lengths(2, i + 1, j)  ! right
          !   edge_lengths(3) = self%grid%cell_edge_lengths(3, i, j + 1)  ! top
          !   edge_lengths(4) = self%grid%cell_edge_lengths(4, i - 1, j)  ! left

          !   edge_normals(:, 1) = self%grid%cell_edge_norm_vectors(:, 1, i, j - 1)  ! bottom
          !   edge_normals(:, 2) = self%grid%cell_edge_norm_vectors(:, 2, i + 1, j)  ! right
          !   edge_normals(:, 3) = self%grid%cell_edge_norm_vectors(:, 3, i, j + 1)  ! top
          !   edge_normals(:, 4) = self%grid%cell_edge_norm_vectors(:, 4, i - 1, j)  ! left

          !   phi_left_right = limit(right - center, center - left)
          !   phi_up_down = limit(bottom - center, center - top)

          !   v_edge(2) = center + 0.5_rk * phi_left_right  ! right
          !   v_edge(4) = center - 0.5_rk * phi_left_right  ! left
          !   v_edge(1) = center - 0.5_rk * phi_up_down  ! bottom
          !   v_edge(3) = center + 0.5_rk * phi_up_down  ! top

          !   do edge = 1, 4
          !     d_dx = d_dx + (v_edge(i) * edge_normals(1, i) * edge_lengths(i))
          !   end do

          ! end if

          ! if (abs(center - top) < EPS .and. abs(center - bottom) < EPS) then
          !   d_dy = 0.0_rk
          ! else
          ! Edge (face) interface data
          edge_lengths(1) = self%grid%cell_edge_lengths(1, i, j - 1)  ! bottom
          edge_lengths(2) = self%grid%cell_edge_lengths(2, i + 1, j)  ! right
          edge_lengths(3) = self%grid%cell_edge_lengths(3, i, j + 1)  ! top
          edge_lengths(4) = self%grid%cell_edge_lengths(4, i - 1, j)  ! left

          edge_normals(:, 1) = self%grid%cell_edge_norm_vectors(:, 1, i, j - 1)  ! bottom
          edge_normals(:, 2) = self%grid%cell_edge_norm_vectors(:, 2, i + 1, j)  ! right
          edge_normals(:, 3) = self%grid%cell_edge_norm_vectors(:, 3, i, j + 1)  ! top
          edge_normals(:, 4) = self%grid%cell_edge_norm_vectors(:, 4, i - 1, j)  ! left

          phi_left_right = limit(right - center, center - left)
          phi_up_down = limit(bottom - center, center - top)

          v_edge(2) = center + 0.5_rk * phi_left_right  ! right
          v_edge(4) = center - 0.5_rk * phi_left_right  ! left
          v_edge(1) = center - 0.5_rk * phi_up_down  ! bottom
          v_edge(3) = center + 0.5_rk * phi_up_down  ! top

          do k = 1, 4
            d_dx = d_dx + (v_edge(k) * edge_normals(1, k) * edge_lengths(k))
            d_dy = d_dy + (v_edge(k) * edge_normals(2, k) * edge_lengths(k))
          end do

          ! end if

        end associate

        gradient(:, i, j) = d_dx / self%grid%cell_volume(i, j)
        gradient(:, i, j) = d_dy / self%grid%cell_volume(i, j)
      end do
    end do
    !$omp end do
    !$omp end parallel

  end subroutine estimate_gradient

  impure elemental function limit(a_0, b_0) result(phi)
    real(rk), intent(in) :: a_0, b_0
    real(rk) :: a, b
    real(rk) :: phi
    real(rk) :: denom
    real(rk), parameter :: tiny_diff = epsilon(1.0_rk) * 5.0_rk

    a = a_0
    b = b_0
    if(abs(a_0) < tiny_diff) a = 0.0_rk
    if(abs(b_0) < tiny_diff) b = 0.0_rk

    if(abs(a - b) < tiny_diff) then
      phi = 0.0_rk
    else
      denom = a**2 + b**2
      if(denom > 0.0_rk) then
        phi = max(a * b, 0.0_rk) * (a + b) / denom
      else
        phi = 0.0_rk
      end if
    end if
  end function

end module mod_second_order_sgg_structured_reconstruction
