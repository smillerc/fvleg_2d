module mod_grid_block_1d

  use iso_fortran_env, only: ik => int32, rk => real64, std_err => error_unit
  use mod_grid_block, only: grid_block_t
  use mod_input, only: input_t

  implicit none

  private
  public :: grid_block_1d_t, new_1d_grid_block

  type, extends(grid_block_t) :: grid_block_1d_t
    real(rk), dimension(:), allocatable :: volume !< (i); volume of each cell
    real(rk), dimension(:), allocatable :: dx     !< (i); dx spacing of each cell
    real(rk), dimension(:), allocatable :: dy     !< (i); dy spacing of each cell
    real(rk), dimension(:), allocatable :: node_x      !< (i); x location of each node
    real(rk), dimension(:), allocatable :: node_y      !< (i); y location of each node
    real(rk), dimension(:), allocatable :: centroid_x  !< (i); x location of the cell centroid
    real(rk), dimension(:), allocatable :: centroid_y  !< (i); y location of the cell centroid
    real(rk), dimension(:, :), allocatable :: edge_lengths         !< ((edge_1:edge_n), i); length of each edge
    real(rk), dimension(:, :, :), allocatable :: edge_norm_vectors !< ((x,y), edge, i); normal direction vector of each face
  contains
    procedure :: initialize => init_1d_block
    final :: finalize_1d_block
  endtype grid_block_1d_t
contains
  function new_1d_grid_block(input) result(grid)
    type(grid_block_1d_t), pointer :: grid
    class(input_t), intent(in) :: input
    allocate(grid)
    call grid%initialize(input)
  endfunction new_1d_grid_block

  subroutine init_1d_block(self, input)
    class(grid_block_1d_t), intent(inout) :: self
    class(input_t), intent(in) :: input

    allocate(self%global_node_dims(1))
    self%global_node_dims = 0
    allocate(self%global_cell_dims(1))
    self%global_cell_dims = 0
    allocate(self%domain_node_shape(1))
    self%domain_node_shape = 0
    allocate(self%domain_cell_shape(1))
    self%domain_cell_shape = 0
    allocate(self%node_lbounds(1))
    self%node_lbounds = 0
    allocate(self%node_ubounds(1))
    self%node_ubounds = 0
    allocate(self%node_lbounds_halo(1))
    self%node_lbounds_halo = 0
    allocate(self%node_ubounds_halo(1))
    self%node_ubounds_halo = 0
    allocate(self%cell_lbounds(1))
    self%cell_lbounds = 0
    allocate(self%cell_ubounds(1))
    self%cell_ubounds = 0
    allocate(self%cell_lbounds_halo(1))
    self%cell_lbounds_halo = 0
    allocate(self%cell_ubounds_halo(1))
    self%cell_ubounds_halo = 0
    allocate(self%on_bc(2, 1))
    self%on_bc = .false.
  endsubroutine

  subroutine finalize_1d_block(self)
    type(grid_block_1d_t), intent(inout) :: self
    if(allocated(self%node_x)) deallocate(self%node_x)
    if(allocated(self%node_y)) deallocate(self%node_y)
    if(allocated(self%volume)) deallocate(self%volume)
    if(allocated(self%dx)) deallocate(self%dx)
    if(allocated(self%dy)) deallocate(self%dy)
    if(allocated(self%centroid_x)) deallocate(self%centroid_x)
    if(allocated(self%centroid_y)) deallocate(self%centroid_y)
    if(allocated(self%edge_lengths)) deallocate(self%edge_lengths)
    if(allocated(self%edge_norm_vectors)) deallocate(self%edge_norm_vectors)
    if(allocated(self%global_node_dims)) deallocate(self%global_node_dims)
    if(allocated(self%global_cell_dims)) deallocate(self%global_cell_dims)
    if(allocated(self%domain_node_shape)) deallocate(self%domain_node_shape)
    if(allocated(self%domain_cell_shape)) deallocate(self%domain_cell_shape)
    if(allocated(self%node_lbounds)) deallocate(self%node_lbounds)
    if(allocated(self%node_ubounds)) deallocate(self%node_ubounds)
    if(allocated(self%node_lbounds_halo)) deallocate(self%node_lbounds_halo)
    if(allocated(self%node_ubounds_halo)) deallocate(self%node_ubounds_halo)
    if(allocated(self%cell_lbounds)) deallocate(self%cell_lbounds)
    if(allocated(self%cell_ubounds)) deallocate(self%cell_ubounds)
    if(allocated(self%cell_lbounds_halo)) deallocate(self%cell_lbounds_halo)
    if(allocated(self%cell_ubounds_halo)) deallocate(self%cell_ubounds_halo)
    if(allocated(self%on_bc)) deallocate(self%on_bc)
  endsubroutine

endmodule mod_grid_block_1d
