using Debug
import PCGA
const EXAMPLEFLAG = 1 

# This runs tests for module PCGA.jl on 2 examples
# Set:
# EXAMPLEFLAG = 1  for 1D deconvolution test problem
# EXAMPLEFLAG = 2  for 2D groundwater forward model

# Last updated July 17, 2015 by Ellen Le
# Questions: ellenble@gmail.com
#
# References: 
# Jonghyun Lee and Peter K. Kitanidis, 
# Large-Scale Hydraulic Tomography and Joint Inversion of Head and
# Tracer Data using the Principal Component Geostatistical Approach
# (PCGA), 
# Water Resources Research, 50(7): 5410-5427, 2014
# Peter K. Kitanidis and Jonghyun Lee, 
# Principal Component Geostatistical Approach for Large-Dimensional
# Inverse Problem, 
# Water Resources Research, 50(7): 5428-5443, 2014

const numparams = 30

tic()

if EXAMPLEFLAG == 1
    using PyPlot
    include("deconvolutionTestProblem.jl")
    noise = 5  #  noise = 5 means 5% of max value
    G,strue,yvec,Gamma,Q = deconv2(numparams,noise);
    Z = PCGA.randSVDzetas(Q); # Random SVD on the prior part covariance matrix
elseif EXAMPLEFLAG == 2
    include("ellen.jl")
    testForward = forwardObsPoints
    Gamma = R
    strue = [truelogk1[1:end]; truelogk2[1:end]] #vectorized 2D parameter field
    yvec = u_obsNoise # see ellen.jl for noise level
    Z = PCGA.randSVDzetas(Q) 
else
    println("example not supported")
end

Zis = Array{Float64, 1}[Z[:,1],Z[:,2]];

for i = 3:size(Z,2)
    Zis = push!(Zis,Z[:,i])
end

#Run the optimization loop until it converges or a total_iter number of times
const total_iter = 5;

mean_s = zeros(length(strue));
 
#choose a random smooth field in the prior to start at
U,S = svd(Q) #assuming Q not perfectly spd
Sh = sqrt(S)
L = U*diagm(Sh)
srand(1)
s0 = mean_s + 0.1* L * randn(length(strue));

relerror = Array(Float64,total_iter+1)
sbar  = Array(Float64,length(strue),total_iter+1)
sbar[:,1] = s0;
relerror[1] = norm(sbar[:,1]-strue)/norm(strue);

for k = 1:total_iter
    sbar[:,k+1] = PCGA.pcgaiteration(testForward, sbar[:,k], mean_s, Zis, Gamma, yvec)
    relerror[k+1] = norm(sbar[:,k+1]-strue)/norm(strue);
end

return sbar,relerror

totaltime_PCGA = toq() 

rel_errPCGA = norm(sbar[:,end]-strue)/norm(strue);
@show(total_iter,rel_errPCGA, totaltime_PCGA)

# Plotting for each example
if EXAMPLEFLAG == 1
    x = linspace(0,1,numparams);
   
    plot(x,strue,x,mean_s,x,sbar[:,1],x,sbar[:,end],linestyle="-",marker="o")
    legend(["sythetic","s_mean","initial s_0 (a random field in the
    prior probability distribution)","s_end"], loc=0)


    xlabel("unit 1D domain x")
    ylabel("1D parameter field s(x)")
    title("PCGA, total iterates = $total_iter, noise = $noise%")
    grid("on")

    figure(2)
    plot(1:total_iter+1,relerror,linestyle="-",marker="o")
    title("Relative error vs iteration number, PCGA method")

elseif EXAMPLEFLAG == 2
    fignum  = 5    

    k1mean, k2mean = x2k(mean_s)
    logk_mean = ks2k(k1mean,k2mean)

    k1s0,k2s0 = x2k(s0)
    logk_s0 = ks2k(k1s0,k2s0)

    k1p_i,k2p_i = x2k(sbar[:,end-1]);
    logkp_i = ks2k(k1p_i,k2p_i);

    k1p,k2p = x2k(sbar[:,end]);
    logkp = ks2k(k1p,k2p);
    
    fig = plt.figure(figsize=(6*fignum, 6))    
    
    plotfield(logk,1,fignum)
    plt.title("the true logk")

    plotfield(logk_mean,2,fignum)
    plt.title("the mean, here truelogk + noise")

    plotfield(logk_s0,3,fignum)
    plt.title("s0 (using prior and mean)")

    plotfield(logkp_i,fignum-1,fignum)
    plt.title("s_end-1")

    plotfield(logkp,fignum,fignum)
    plt.title("the last iterate, total_iter = $total_iter")

    vmin = minimum(logk)
    vmax = maximum(logk)
    plt.clim(vmin, vmax)
    #plt.colorbar() #this makes the resizing weird
    plt.suptitle("2D example", fontsize=16)        

    plt.show()    
  
else
    println("example not supported")
end

