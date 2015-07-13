#module PCGA
#Definetly not array optimized
using Debug


const numparams = 30
const noise = 4
const delta = sqrt(eps())

#close("all")

# Which example to run PCGA on
# 1 = deconvolution test problem
# 2 = ellen.jl forward model
const EXAMPLEFLAG = 2 

# Inputs into pcgaiteration 
# forwardmodel - param to obs map
#            s - current iterate          
#            X - mean of parameter prior (replace with B*X drift matrix
# later for p>1)
#          xis - K columns of Z where Q approx= ZZ^T
#            R - covariance of measurement error (data misfit term)
#            y - data vector            
tic()

function colnorms(Y)
    norms = Array(Float64, size(Y, 2))
    for i = 1:size(Y, 2)
	norms[i] = norm(Y[:, i])
    end
    return norms
end

function rangefinder(A; epsilon=1e-10, r=20)#implements algorithm 4.2 in halko et al
    m = size(A, 1)
    n = size(A, 2)
    Omega = randn(n, r)
    Y = A * Omega
    j = 0
    Q = Array(Float64, m, 0)
    while max(colnorms(Y[:, j+1:j+r])...) > epsilon / sqrt(200 / pi)
	j = j + 1
	Y[:, j] = (eye(m) - Q * ctranspose(Q)) * Y[:, j]
	q = Y[:, j] / norm(Y[:, j])
	Q = [Q q]

	Omega = [Omega randn(n)]
	ynew = (eye(m) - Q * ctranspose(Q)) * A * Omega[:, j + r]
	Y = [Y ynew]
	for i = j + 1:j + r - 1
	    Y[:, i] = Y[:, i] - Q[:, j] * dot(Q[:, j], Y[:, i])
	end
    end
    return Q
end

#Problem: rangefinder giving a matrix of size (840 by 0) when inputting C
function randSVDzetas(A; epsilon=1e-10, r=15)
    Q = rangefinder(A; epsilon=1e-10, r=15);
    B = Q' * A;
    (),S,V = svd(B);
    Sh = diagm(sqrt(S))
    Z = V*Sh 
    return Z
end  

if EXAMPLEFLAG == 1
    using PyPlot
    include("deconvolutionTestProblem.jl")
    G,strue,yvec,Gamma,C = deconv2(numparams,noise);
    Z = randSVDzetas(C); #Do random SVD on the prior part covariance matrix
elseif EXAMPLEFLAG == 2
    #     this_dir = dirname(@__FILE__);
    # include(abspath(joinpath(this_dir,
    # "../finitedifference2d.jl/ellen.jl")))
    include(abspath("../finitedifference2d.jl/ellen.jl"))
    testForward = forwardObsPoints
    Gamma = R
    strue = [truelogk1[1:end]; truelogk2[1:end]] #vectorized 2D
    #parameter field
    yvec = u_obsNoise #see ellen.jl for noise level
    Z = randSVDzetas(Q) 
else
    println("example not supported")
end

# @debug function pcgaiteration(s, X, xis, R, y; forwardmodel = testForward)
function pcgaiteration(forwardmodel::Function,s::Vector, X::Vector, xis::Array{Array{Float64, 1}, 1}, R::Matrix, y::Vector)
    # Inputs: 
    # forwardmodel - param to obs map h(s)
    #            s - current iterate s_k or sbar          
    #            X - mean of parameter prior (replace with B*X drift matrix
    # later for p>1)
    #          xis - K columns of Z where Q approx= ZZ^T, get this by doing
    #          random SVD on your prior covariance matrix and save the
    #          columns in a list xis = [col1,col2,....]
    #            R - covariance of measurement error (data misfit term)
    #            y - data vector
    #tic()     
    global delta
    p = 1
    K = length(xis)
    m = length(xis[1])
    #paramstorun = Array{Float64, 1}[s .+ delta .* xis,{s,s + delta * X, s + delta * s}]
    paramstorun = Array(Array{Float64, 1}, length(xis) + 3)
    for i = 1:length(xis)
	paramstorun[i] = s + delta * xis[i]
    end
    paramstorun[length(xis) + 1] = s
    paramstorun[length(xis) + 2] = s + delta * X
    paramstorun[length(xis) + 3] = s + delta * s
    results = pmap(forwardmodel, paramstorun)
    n = length(results[1])
    # etai = Array(Float64, m)   
    HQHpR = R
    HQ = zeros(n, m)
    for i = 1:K
	etai = (results[i] - results[K+1]) / delta
        #toc()
        #@bp
	HQ += etai * transpose(xis[i])
	HQHpR += etai * transpose(etai)
    end
    # @bp #These matrix products are good 1e-10 order: 
    #  norm(HQ-G*C)
    # norm(HQHpR-(G*C*G'+Gamma)) 
    HX = (results[end-1] - results[end-2]) / delta
    # @bp #This is 0 now, was an error here
    # norm(forwardmodel(X)-HX)/norm(forwardmodel(X))
    Hs = (results[end] - results[K+1]) / delta
    # @bp
    bigA = [HQHpR HX; transpose(HX) zeros(p, p)]
    b = [y - results[1] + Hs; zeros(p)]
    #@bp   
    x = bigA \ b # we will replace this with a Krylov solver or something
    # like UMFPACK?
    s_new = X * x[end] + (HQ)'* x[1:end-1]
    #println(s_new - s)
    return s_new #HQ,HQHpR
end

Zis = Array{Float64, 1}[Z[:,1],Z[:,2]];

for i = 3:size(Z,2)
    Zis = push!(Zis,Z[:,i])
end


#Runs the optimization loop until it converges
const total_iter = 1;
#s0 = strue+0.05*randn(length(strue));
#s0 = 0.5*ones(length(strue));
s0 = zeros(length(strue));
relerror = Array(Float64,total_iter+1)
sbar  = Array(Float64,length(strue),total_iter+1)
sbar[:,1] = s0;
relerror[1] = norm(sbar[:,1]-strue)/norm(strue);

for k = 1:total_iter
    #tic() 
   sbar[:,k+1] = pcgaiteration(testForward, sbar[:,k], strue, Zis, Gamma, yvec)
    #toc()
    relerror[k+1] = norm(sbar[:,k+1]-strue)/norm(strue);
end

return sbar,relerror

# this doesn't work need to check formation of etas
#  norm(HQHpR-(A'*C*A+Gamma))
# 2.059780712550066e18

toc()
rel_errPCGA = norm(sbar[:,end]-strue)/norm(strue);
@show(rel_errPCGA)

if EXAMPLEFLAG == 1
    x = linspace(0,1,numparams);
    plot(x,strue,x,sbar[:,1],x,sbar[:,end-2],x,sbar[:,end-1],x,sbar[:,end],linestyle="-",marker="o")
    legend(["sythetic","initial s_0","s_end-2","s_end-1","s_end"], loc=0)
    xlabel("unit 1D domain x")
    ylabel("1D parameter field s(x)")
    title("PCGA, total iterates = $total_iter, noise = $noise%")
    grid("on")

    figure(2)
    plot(1:total_iter+1,relerror,linestyle="-",marker="o")
    title("Relative error vs iteration number, PCGA method")

elseif EXAMPLEFLAG == 2
    k1p,k2p = x2k(sbar[:,end]);
    logkp = ks2k(k1p,k2p);
    fig = plt.figure(figsize=(24, 12))
    plotfield(logk,1,2)
    plotfield(logkp,2,2)
    #plt.colorbar() this makes the resizing weird
    plt.show()
else
    println("example not supported")
end

