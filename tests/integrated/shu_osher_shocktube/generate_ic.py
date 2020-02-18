# -*- coding: utf-8 -*-
"""Make the 1D Shu-Osher Shock Tube"""
import matplotlib.pyplot as plt
import numpy as np
import sys
import os

sys.path.append(os.path.abspath("../../../scripts"))
from generate_initial_grids import make_1d_in_x_uniform_grid, write_initial_hdf5

# Make the empty grid
shock_tube = make_1d_in_x_uniform_grid(n_cells=2000, limits=(0, 1.0))

# Set the initial conditions
epsilon = 0.2
shock_tube["v"] = shock_tube["v"] * 0.0
gamma = 1.4
x = shock_tube["xc"]
y = shock_tube["yc"]

for i in range(y.shape[0]):
    for j in range(y.shape[1]):
        # Left State
        if x[i, j] < 1 / 8:
            shock_tube["u"][i, j] = 2.629369
            shock_tube["p"][i, j] = 10.3333
            shock_tube["rho"][i, j] = 3.857143
        # Right state
        else:
            shock_tube["u"][i, j] = 0.0
            shock_tube["p"][i, j] = 1.0
            shock_tube["rho"][i, j] = 1.0 + 0.2 * np.sin(8.0 * x[i, j] * 2.0 * np.pi)

bc_dict = {"+x": "periodic", "+y": "periodic", "-x": "periodic", "-y": "periodic"}

write_initial_hdf5(
    filename="initial_conditions",
    initial_condition_dict=shock_tube,
    boundary_conditions_dict=bc_dict,
)

# Plot the results
fig, (ax1, ax2) = plt.subplots(figsize=(18, 8), nrows=2, ncols=1)
for ax, v in zip([ax1, ax2], ["rho", "p"]):
    vc = ax.plot(shock_tube["xc"][1, :], shock_tube[v][1, :])
    ax.set_ylabel(v)
    ax.set_xlabel("X")

plt.show()
