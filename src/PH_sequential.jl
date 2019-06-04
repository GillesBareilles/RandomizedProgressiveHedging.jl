include("RPH.jl")

function subproblem_solve(pb, id_scen, u_scen, x_scen, μ, params)
    n = sum(length.(pb.stage_to_dim))
    
    ## Regalurized problem
    model = Model(with_optimizer(Ipopt.Optimizer, print_level=0))

    # Get scenario objective function, build constraints in model
    y, obj, ctrref = build_fs_Cs!(model, pb.scenarios[id_scen], id_scen)
    
    # Augmented lagragian subproblem full objective
    obj += dot(u_scen, y) + (1/2*μ) * sum((y[i]-x_scen[i])^2 for i in 1:n)
    @objective(model, Min, obj)
    
    optimize!(model)

    y_new = JuMP.value.(y)
    return y_new
end

"""
nonanticipatory_projection!(x::Matrix{Float64}, pb::Problem, y::Matrix{Float64})

Store in `x` the projection of `y` on the non-anticipatory subspace associated to problem `pb`.
"""
function nonanticipatory_projection!(x::Matrix{Float64}, pb::Problem, y::Matrix{Float64})
    @assert size(x) == size(y) "nonanticipatory_projection!(): input and output arrays should have same size"
    depth_to_partition = get_partitionbydepth(pb.scenariotree)

    for (stage, scen_partition) in enumerate(depth_to_partition)
        stage_dims = pb.stage_to_dim[stage]
        for scen_set in scen_partition
            averaged_traj = sum(pb.probas[i]*y[i, stage_dims] for i in scen_set) / sum(pb.probas[i] for i in scen_set)
            for scen in scen_set
                x[scen, stage_dims] = averaged_traj
            end
        end
    end
    return
end

"""
nonanticipatory_projection(pb::Problem, y::Matrix{Float64})

Compute the projection of `y` on the non-anticipatory subspace associated to problem `pb`.
"""
function nonanticipatory_projection(pb::Problem, y::Matrix{Float64})
    x = zeros(size(y))
    nonanticipatory_projection!(x, pb, y)
    return x
end


function PH_sequential_solve(pb)
    println("----------------------------")
    println("--- PH sequential solve")
    
    # parameters
    μ = 3
    params = Dict(
        :print_step => 10
    )

    # Variables
    nstages = pb.nstages
    nscenarios = pb.nscenarios

    y = zeros(Float64, nstages, nscenarios)
    x = zeros(Float64, nstages, nscenarios)
    u = zeros(Float64, nstages, nscenarios)
    
    # Initialization
    # y = subproblems per scenario
    # nonanticipatory_projection!(x, pb, y)

    it = 0
    @printf " it   primal res        dual res            dot(x,u)   objective\n"
    while it < 100
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
        objval = objective_value(pb, x)
        primres = norm(pb, x-y)
        dualres = (1/μ) * norm(pb, u - u_old)
        dot_xu = dot(pb, x, u)
        
        if mod(it, params[:print_step]) == 0
            @printf "%3i   %.10e  %.10e   % .3e % .16e\n" it primres dualres dot_xu objval
        end

        it += 1
    end

    return x
end