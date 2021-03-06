! MIT License
! Copyright (c) 2019 Sam Miller
! Permission is hereby granted, free of charge, to any person obtaining a copy
! of this software and associated documentation files (the "Software"), to deal
! in the Software without restriction, including without limitation the rights
! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
! copies of the Software, and to permit persons to whom the Software is
! furnished to do so, subject to the following conditions:
!
! The above copyright notice and this permission notice shall be included in all
! copies or substantial portions of the Software.
!
! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
! SOFTWARE.

module mod_farfield
  !< Summary: Provide the procedures for farfield boundary conditions
  !< Date: 04/23/2020
  !< Author: Sam Miller
  !< Notes:
  !< References:
  !      [1]
  implicit none

  private
  ! public :: farfield ! only the ff is exposed, the others are used internaly

contains
  ! function farfield() result(boundary_prim_vars)
  ! end function farfield

  ! function subsonic_outflow() result(boundary_prim_vars)
  ! end function subsonic_outflow

  ! function subsonic_inflow() result(boundary_prim_vars)
  ! end function subsonic_inflow

  ! function supersonic_outflow() result(boundary_prim_vars)
  ! end function supersonic_outflow

  ! function supersonic_inflow() result(boundary_prim_vars)
  ! end function supersonic_inflow

endmodule mod_farfield
