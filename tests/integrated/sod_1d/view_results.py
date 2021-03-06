# -*- coding: utf-8 -*-
"""
A simple script to view the results from the simulation
"""

import h5py
import numpy as np
import os
import pytz
from datetime import datetime
import matplotlib.pyplot as plt
import os, sys
import sod
import subprocess

sys.path.append("../../..")
from pycato import *

tz = pytz.timezone("America/New_York")
now = datetime.now(tz)

try:
    short_hash = (
        subprocess.check_output(["git", "rev-parse", "--short", "HEAD"])
        .decode("utf-8")
        .strip()
    )
except Exception:
    short_hash = "N/A"

try:
    branch = (
        subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"])
        .decode("utf-8")
        .strip()
    )

    if branch == "HEAD":
        branch = os.getenv("CI_COMMIT_REF_NAME")
    if branch is None:
        branch = "N/A"

except Exception:
    branch = "N/A"

try:
    walltime_sec = np.loadtxt("timing.csv", delimiter=",", skiprows=1)[-1][1]
except Exception:
    walltime_sec = "N/A"

# Load cato results
from dask.diagnostics import ProgressBar

with ProgressBar():
    ds = load_multiple_steps("results/step*.h5", ini_file="input.ini")

# try:
scheme = f"{ds.attrs['scheme_flux_solver']}({ds.attrs['scheme_spatial_reconstruction']} {ds.attrs['scheme_limiter']})"
# except Exception:
#     scheme = None

t = 0.2
actual_time = ds.density.sel(time=t, method="nearest").time.data

gamma = 1.4
npts = 500

# exact results
positions, regions, values = sod.solve(
    left_state=(1, 1, 0),
    right_state=(0.1, 0.125, 0.0),
    geometry=(0.0, 1.0, 0.5),
    t=actual_time,
    gamma=gamma,
    npts=npts,
)
p = values["p"]
rho = values["rho"]
u = values["u"]


plt.figure(figsize=(12, 6))

ds.density.sel(time=t, method="nearest").plot(x="x", label="CATO Density")
plt.plot(values["x"], rho, label="Exact Density")

ds.x_velocity.sel(time=t, method="nearest").plot(x="x", label="CATO Velocity")
plt.plot(values["x"], u, label="Exact Velocity")

ds.pressure.sel(time=t, method="nearest").plot(x="x", label="CATO Pressure")
plt.plot(values["x"], p, label="Exact Pressure")

plt.title(
    f"Sod 1D Test @ {now} \nsimulation t={actual_time:.2f} s \nwalltime={walltime_sec} s\nbranch: {branch} \ncommit: {short_hash} \nscheme: {scheme}"
)
plt.ylabel("")
plt.xlabel("X")
plt.ylim((-0.1, 1.2))
plt.legend()
plt.tight_layout()
plt.savefig("sod_1d_results.png")