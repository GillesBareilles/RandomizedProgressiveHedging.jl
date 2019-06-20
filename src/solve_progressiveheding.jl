function subproblem_solve(pb, id_scen, u_scen, x_scen, μ, params)
    n = sum(length.(pb.stage_to_dim))
    
    ## Regalurized problem
    model = Model(with_optimizer(Ipopt.Optimizer, print_level=0))

    # Get scenario objective function, build constraints in model
    y, obj, ctrref = pb.build_subpb(model, pb.scenarios[id_scen], id_scen)
    
    # Augmented lagragian subproblem full objective
    obj += dot(u_scen, y) + (1/2*μ) * sum((y[i]-x_scen[i])^2 for i in 1:n)
    @objective(model, Min, obj)
    
    optimize!(model)

    y_new = JuMP.value.(y)
    return y_new
end


"""
    x = solve_progressivehedging(pb::Problem)

Run the classical Progressive Hedging scheme on problem `pb`. 

Stopping criterion is based on primal dual residual, maximum iterations or time 
can also be set. Return a feasible point `x`.

## Keyword arguments:
- `ϵ_primal`: Tolerance on primal residual.
- `ϵ_dual`: Tolerance on dual residual.
- `μ`: Regularization parameter.
- `tlim`: Limit time spent in computations.
- `maxiter`: Maximum iterations.
- `printlev`: if 0, mutes output.
- `printstep`: number of iterations skipped between each print and logging.
- `hist`: if not nothing, will record:
    + `:functionalvalue`: array of functional value indexed by iteration,
    + `:time`: array of time at the end of each iteration, indexed by iteration,
    + `:dist_opt`: if dict has entry `:approxsol`, array of distance between iterate and `hist[:approxsol]`, indexed by iteration.
    + `:logstep`: number of iteration between each log.
"""
function solve_progressivehedging(pb::Problem; ϵ_primal = 1e-3,
                                               ϵ_dual = 1e-3,
                                               μ = 3,
                                               tlim = 3600,
                                               maxiter = 1e3,
                                               printlev = 1,
                                               printstep = 1,
                                               hist::Union{OrderedDict{Symbol, Any}, Nothing}=nothing)
    printlev>0 && println("--------------------------------------------------------")
    printlev>0 && println("--- Progressive Hedging")
    printlev>0 && println("--------------------------------------------------------")
    
    # Variables
    nstages = pb.nstages
    nscenarios = pb.nscenarios
    n = sum(length.(pb.stage_to_dim))

    y = zeros(Float64, nscenarios, n)
    x = zeros(Float64, nscenarios, n)
    u = zeros(Float64, nscenarios, n)
    primres = dualres = Inf

    tinit = time()
    !isnothing(hist) && (hist[:functionalvalue] = Float64[])
    !isnothing(hist) && (hist[:time] = Float64[])
    !isnothing(hist) && haskey(hist, :approxsol) && (hist[:dist_opt] = Float64[])
    !isnothing(hist) && (hist[:logstep] = printstep)

    it = 0
    printlev>0 && @printf " it   primal res        dual res            dot(x,u)   objective\n"
    while !(primres < ϵ_primal && dualres < ϵ_dual) && it < maxiter && time()-tinit < tlim
        u_old = copy(u)

        # Subproblem solves
        for id_scen in 1:nscenarios
            y[id_scen, :] = subproblem_solve(pb, id_scen, u[id_scen, :], x[id_scen, :], μ, params)
        end

        # projection on non anticipatory subspace
        nonanticipatory_projection!(x, pb, y)

        # multiplier update
        u += (1/μ) * (y-x)

        
        # invariants, indicators
        primres = norm(pb, x-y)
        dualres = (1/μ) * norm(pb, u - u_old)
        if mod(it, printstep) == 0
            objval = objective_value(pb, x)
            dot_xu = dot(pb, x, u)

            printlev>0 && @printf "%3i   %.10e  %.10e   % .3e % .16e\n" it primres dualres dot_xu objval

            !isnothing(hist) && push!(hist[:functionalvalue], objval)
            !isnothing(hist) && push!(hist[:time], time() - tinit)
            !isnothing(hist) && haskey(hist, :approxsol) && push!(hist[:dist_opt], norm(hist[:approxsol] - x))
        end

        it += 1
    end

    ## Final print
    objval = objective_value(pb, x)
    dot_xu = dot(pb, x, u)

    printlev>0 && @printf "%3i   %.10e  %.10e   % .3e % .16e\n" it primres dualres dot_xu objval
    printlev>0 && println("Computation time: ", time() - tinit)

    return x
end