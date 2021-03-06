# Principal Component Analysis

#### PCA type

type PCA{T<:AbstractFloat}
    mean::Vector{T}       # sample mean: of length d (mean can be empty, which indicates zero mean)
    proj::Matrix{T}       # projection matrix: of size d x p
    prinvars::Vector{T}   # principal variances: of length p
    tprinvar::T           # total principal variance, i.e. sum(prinvars)
    tvar::T               # total input variance
end

## constructor

function PCA{T<:AbstractFloat}(mean::Vector{T}, proj::Matrix{T}, pvars::Vector{T}, tvar::T)
    d, p = size(proj)
    (isempty(mean) || length(mean) == d) ||
        throw(DimensionMismatch("Dimensions of mean and proj are inconsistent."))
    length(pvars) == p ||
        throw(DimensionMismatch("Dimensions of proj and pvars are inconsistent."))
    tpvar = sum(pvars)
    tpvar <= tvar || isapprox(tpvar,tvar) || throw(ArgumentError("principal variance cannot exceed total variance."))
    PCA(mean, proj, pvars, tpvar, tvar)
end

## properties

indim(M::PCA) = size(M.proj, 1)
outdim(M::PCA) = size(M.proj, 2)

Base.mean(M::PCA) = fullmean(indim(M), M.mean)

projection(M::PCA) = M.proj

principalvar(M::PCA, i::Int) = M.prinvars[i]
principalvars(M::PCA) = M.prinvars

tprincipalvar(M::PCA) = M.tprinvar
tresidualvar(M::PCA) = M.tvar - M.tprinvar
tvar(M::PCA) = M.tvar

principalratio(M::PCA) = M.tprinvar / M.tvar

## use

transform{T<:AbstractFloat}(M::PCA{T}, x::AbstractVecOrMat{T}) = At_mul_B(M.proj, centralize(x, M.mean))
reconstruct{T<:AbstractFloat}(M::PCA{T}, y::AbstractVecOrMat{T}) = decentralize(M.proj * y, M.mean)

## show & dump

function show(io::IO, M::PCA)
    pr = @sprintf("%.5f", principalratio(M))
    print(io, "PCA(indim = $(indim(M)), outdim = $(outdim(M)), principalratio = $pr)")
end

function dump(io::IO, M::PCA)
    show(io, M)
    println(io)
    print(io, "principal vars: ")
    printvecln(io, M.prinvars)
    println(io, "total var = $(tvar(M))")
    println(io, "total principal var = $(tprincipalvar(M))")
    println(io, "total residual var  = $(tresidualvar(M))")
    println(io, "mean:")
    printvecln(io, mean(M))
    println(io, "projection:")
    printarrln(io, projection(M))
end


#### PCA Training

## auxiliary

const default_pca_pratio = 0.99

function check_pcaparams{T<:AbstractFloat}(d::Int, mean::Vector{T}, md::Int, pr::AbstractFloat)
    isempty(mean) || length(mean) == d ||
        throw(DimensionMismatch("Incorrect length of mean."))
    md >= 1 || error("maxoutdim must be a positive integer.")
    0.0 < pr <= 1.0 || throw(ArgumentError("pratio must be a positive real value with pratio ≤ 1.0."))
end


function choose_pcadim{T<:AbstractFloat}(v::AbstractVector{T}, ord::Vector{Int}, vsum::T, md::Int, pr::AbstractFloat)
    md = min(length(v), md)
    k = 1
    a = v[ord[1]]
    thres = vsum * pr
    while k < md && a < thres
        a += v[ord[k += 1]]
    end
    return k
end


## core algorithms

function pcacov{T<:AbstractFloat}(C::DenseMatrix{T}, mean::Vector{T};
                maxoutdim::Int=size(C,1),
                pratio::AbstractFloat=default_pca_pratio)

    check_pcaparams(size(C,1), mean, maxoutdim, pratio)
    Eg = eigfact(Symmetric(C))
    ev = Eg.values
    ord = sortperm(ev; rev=true)
    vsum = sum(ev)
    k = choose_pcadim(ev, ord, vsum, maxoutdim, pratio)
    v, P = extract_kv(Eg, ord, k)
    PCA(mean, P, v, vsum)
end

function pcasvd{T<:AbstractFloat}(Z::DenseMatrix{T}, mean::Vector{T}, tw::Real;
                maxoutdim::Int=min(size(Z)...),
                pratio::AbstractFloat=default_pca_pratio)

    check_pcaparams(size(Z,1), mean, maxoutdim, pratio)
    Svd = svdfact(Z)
    v = Svd.S::Vector{T}
    U = Svd.U::Matrix{T}
    for i = 1:length(v)
        @inbounds v[i] = abs2(v[i]) / tw
    end
    ord = sortperm(v; rev=true)
    vsum = sum(v)
    k = choose_pcadim(v, ord, vsum, maxoutdim, pratio)
    si = ord[1:k]
    PCA(mean, U[:,si], v[si], vsum)
end

## interface functions

function fit{T<:AbstractFloat}(::Type{PCA}, X::DenseMatrix{T};
             method::Symbol=:auto,
             maxoutdim::Int=size(X,1),
             pratio::AbstractFloat=default_pca_pratio,
             mean=nothing)

    d, n = size(X)

    # choose method
    if method == :auto
        method = d < n ? :cov : :svd
    end

    # process mean
    mv = preprocess_mean(X, mean)

    # delegate to core
    if method == :cov
        if VERSION < v"0.5.0-dev+660"
            C = cov(X; vardim=2, mean=isempty(mv) ? 0 : mv)::Matrix{T}
        else
            C = Base.covm(X, isempty(mv) ? 0 : mv, 2)
        end
        M = pcacov(C, mv; maxoutdim=maxoutdim, pratio=pratio)
    elseif method == :svd
        Z = centralize(X, mv)
        M = pcasvd(Z, mv, n; maxoutdim=maxoutdim, pratio=pratio)
    else
        throw(ArgumentError("Invalid method name $(method)"))
    end

    return M::PCA
end
