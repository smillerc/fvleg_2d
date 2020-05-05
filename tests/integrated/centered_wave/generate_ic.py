# -*- coding: utf-8 -*-
"""Make the double periodic shear test grid"""
import matplotlib.pyplot as plt
import numpy as np
import sys
import os

sys.path.append(os.path.abspath("../../.."))
from scripts import make_uniform_grid, write_initial_hdf5, ureg

# Make the empty grid
domain = make_uniform_grid(n_cells=(200, 200), xrange=(-0.5, 0.5), yrange=(-0.5, 0.5))

# Set the initial conditions
domain["rho"] = domain["rho"] * 0.001
# domain["p"] = domain["p"] * .001
p0 = 1e-3
domain["x"] = domain["x"]
domain["y"] = domain["y"]
x = domain["xc"]
y = domain["yc"]

# Make pressure a centered gaussian with surrounding pressure of 1.0
# domain["p"] = np.exp(-(x**2 + y**2)) * 1.0e6 + 1e6# 1 atm
p = 10 * np.exp(-((x.m ** 2) / 0.001 + (y.m ** 2) / 0.001)) + p0
domain["p"] = p * ureg(str(domain["p"].units))

# Zero velocity everywhere
domain["u"] = domain["u"] * 0.0
domain["v"] = domain["v"] * 0.0

write_initial_hdf5(filename="sedov", initial_condition_dict=domain)

# Plot the results
# fig, (ax1) = plt.subplots(figsize=(18, 8), nrows=1, ncols=1)

# vc = ax1.pcolormesh(
#     domain["x"],
#     domain["y"],
#     domain["p"],
#     edgecolor="k",
#     lw=0.001,
#     cmap="RdBu",
#     antialiased=True,
# )
# fig.colorbar(vc, ax=ax1, label="Pressure")
# ax1.set_xlabel("X")
# ax1.set_ylabel("Y")
# ax1.axis("equal")
# plt.show()
